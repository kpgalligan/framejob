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
//       the next word's tick scrolls nothing. F10's and F14's views keep the
//       idle pass OFF (`longView(idle: false)`): their far text must be an
//       estimate when the row acts.
//   F15 the follow at the text's ends (#584), the same words laid out whole by
//       the idle pass, `layoutSteps` counting `layOut(through:)`: (a) two ticks
//       on the first words at scroll 0 add no step (in a 600 pt view the first
//       line is inside the margin already, so this letter holds before the fix
//       too); (c) the control, a tick on token 18,000 adds one and scrolls;
//       (b) two ticks on the last words with the view's bottom at the visible
//       bottom add no step and scroll nothing; (d) on a view NOT laid out
//       whole, its frame cut to the visible bottom by hand, a tick on the last
//       token still steps and shows it.
//   F16 the whole layout in idle time (#583), against a REFERENCE view laid
//       out in one run from the top at scroll 0 with the pass off: (a) as
//       `show` returns no pass has run and the view is short; after a run-loop
//       turn one has, and the height is the reference's; (b) `scrollToToken`
//       18,000 puts the visible top and the scroller's knob where the
//       reference says; (c) a rebuild there with word 5 removed, far words
//       measured before the pass as the pane's highlight does: the same top
//       word at its old offset, it, token 26,000 and the height where a second
//       reference (the edited words) has them; (d) two rebuilds in one turn
//       cost one pass; (f) a scroll between a rebuild and its pass wins; (e) a
//       width change leaves the view not whole until a turn, and one landing
//       between a rebuild and its pass keeps the rebuild's anchor; (g) a width
//       change with no rebuild pending keeps the top word (#593), against
//       references laid out at 340 and 322 pt too: (g1) word 18,000 in sight at
//       its offset straight after 304 → 340, (g2) after a turn the same word at
//       its offset and the 340 pt reference's place and height, (g3) a drag's
//       steps 340 → 322 → 304 with no turn between, the word at its offset
//       straight after each and after the turn, (g4) a scroll before the
//       pass wins, (g5) a drag 304 → 322 → 304 from a word that starts a line
//       at 304 pt and not at 322 pt; (h) in a legacy autohiding scroll view, as
//       the pane's on such a host, a rebuild from ten words to 27,000 shows the
//       scroller inside `show`, and `show`'s anchor still wins. Its detail
//       prints a pass's time and added footprint.
//   F17 ⌘Return in the find field (#559, TX-43), each letter's verdict in the
//       detail: (a) offered as `NSApplication` offers a ⌘ key first,
//       `window.performKeyEquivalent(with:)` answering true: the current match
//       selected, the playhead at its first word, the in/out range set, the
//       transcript's text first responder, the bar open on the same current
//       match and count; (b) the same through `sendEvent` alone; (c) "Café
//       Noir", both words selected, the playhead at the first; (d) "afé", the
//       whole word; (e) no match: nothing moved, the field keeping the keys;
//       (f) ⌘⇧Return taken at neither door, nothing selected; (g) the first Esc
//       clears the selection and the next closes the bar, and after another
//       ⌘Return ⌫ makes one "Delete Words" (undone after). (c)–(g) press as
//       `NSApplication` does: the key-equivalent door, then `sendEvent`.
//   F18 Edit ▸ Find… on the Media tab (#560, TX-45): (a) the validator false
//       on Clip, Document and Assistant, true on Media and Transcript; (b) a
//       name typed in Search by name and the keys handed back, the action gives
//       the field the keys with its whole text selected, and pressed again
//       with the caret at the end selects it all again; (c) typing there
//       narrows the rows; (d) Return hands the keys to the content view and
//       Space plays; (e) the Media section shut, by a volatile argument-domain
//       default (no preference written): the validator false, the action
//       moving no keys; (f) the same with the inspector's container hidden
//       (not Hide Inspector, which writes a default); (g) the pane made taller
//       than the inspector and scrolled to its foot, the action brings the
//       field back into sight.
import AppKit

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()

var rows: [[String: Any]] = []
func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(4000))])
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

/// F10's 27,000 words in 900 paragraphs, one of them left out for a rebuild.
func longWords(without dropped: Int? = nil) -> [TimelineTranscript.Word] {
    var words: [TimelineTranscript.Word] = []
    words.reserveCapacity(27_000)
    for paragraph in 0..<900 {
        for n in 0..<30 where paragraph * 30 + n != dropped {
            let at = Double(paragraph) * 4 + Double(n) * 0.08
            words.append(word("w\(paragraph)x\(n)", at, at + 0.06, clip: UInt32(100 + paragraph)))
        }
    }
    return words
}

/// A bare `TranscriptView` in a 304 × 600 scroll view showing 27,000 words in
/// 900 paragraphs, drawn nowhere yet. F10 and each of F14's targets take a
/// fresh one: once a reveal has laid a view out, nothing in it is an estimate.
/// For the same reason the idle pass that lays the whole text out (#583) is
/// OFF unless `idle`: F10's and F14's mutants are caught only on a view whose
/// far text is still an estimate. `settle` 0 returns before any run-loop turn.
func longView(idle: Bool = false, settle: Double = 0.2, width: CGFloat = 304)
    -> (window: NSWindow, view: TranscriptView, model: TranscriptTokens)
{
    let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: 0, width: width, height: 600), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
    scroll.hasVerticalScroller = true
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 600))
    view.autoresizingMask = [.width]
    scroll.documentView = view
    window.contentView = scroll
    window.orderFrontRegardless()
    let model = TranscriptTokens.build(longWords(), pauses: [:])
    view.laysOutWhenIdle = idle
    view.show(model, fps: Fps(num: 30, den: 1), timecodeFrames: true)
    spin(settle)
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

// MARK: - F15, F16 the whole layout in idle time and the follow at the ends (#583, #584)

/// A view of the same words laid out in ONE run from the top at scroll 0, the
/// idle pass off: nothing in it was ever placed from an estimate, so its
/// height and places are what F15 and F16 compare against (never the view
/// under test laid out again). `width` is the window's, as `longView`'s.
func referenceView(without dropped: Int? = nil, width: CGFloat = 304)
    -> (window: NSWindow, view: TranscriptView)
{
    let (window, view, _) = longView(width: width)
    if dropped != nil {
        view.show(
            TranscriptTokens.build(longWords(without: dropped), pauses: [:]),
            fps: Fps(num: 30, den: 1), timecodeFrames: true)
    }
    view.layoutManager.ensureLayout(for: view.layoutManager.documentRange)
    view.layoutViewport()
    return (window, view)
}

/// A bare `TranscriptView` with no text yet in a 304 × 600 scroll view whose
/// scroller is legacy and hides itself, as the pane's does on a host with
/// legacy scrollers: it shows once the text is taller than the clip, and the
/// view narrows by its width (F16 (h)).
func legacyView(idle: Bool) -> (window: NSWindow, view: TranscriptView) {
    let window = NSWindow(
        contentRect: NSRect(x: -20_000, y: 0, width: 304, height: 600), styleMask: [.titled],
        backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 304, height: 600))
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .legacy
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 600))
    view.autoresizingMask = [.width]
    scroll.documentView = view
    window.contentView = scroll
    window.orderFrontRegardless()
    view.laysOutWhenIdle = idle
    return (window, view)
}

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

func f1(_ value: CGFloat) -> String { String(format: "%.1f", value) }
func settleWhole(_ view: TranscriptView) {
    _ = until(5) { view.laidOutWhole }
    spin(0.1)
}
func clipTop(_ view: TranscriptView) -> CGFloat { view.enclosingScrollView?.contentView.bounds.minY ?? -1 }
let fps30 = Fps(num: 30, den: 1)

do {
    var pass = true
    var detail = ""
    func claim(_ letter: String, _ ok: Bool, _ text: String) {
        pass = pass && ok
        detail += "(\(letter)) \(ok ? "ok" : "FAIL") \(text). "
    }
    let (window, view, _) = longView(idle: true)
    settleWhole(view)
    let whole = view.laidOutWhole && view.wholeLayouts == 1
    // (a) the first words at scroll 0: inside the top margin, nowhere to scroll.
    var steps = view.layoutSteps
    view.setHighlight(0, follow: true)
    view.setHighlight(1, follow: true)
    claim("a", whole && view.layoutSteps == steps && clipTop(view) == 0,
        "whole \(whole); two ticks on tokens 0, 1 at the top: steps +\(view.layoutSteps - steps) "
            + "(want 0), top \(f1(clipTop(view))); token 0's line starts at "
            + "\(f1(view.rects(forToken: 0).first?.minY ?? -1)) pt")
    // (c) the control: a tick that does scroll pays the step.
    steps = view.layoutSteps
    view.setHighlight(18_000, follow: true)
    let moved = clipTop(view)
    // The step's run from the top keeps a whole text whole: the height is
    // still the reference's, read before anything lays the text out again.
    let (referenceWindow, reference) = referenceView()
    let wholeHeight = reference.frame.height
    referenceWindow.orderOut(nil)
    let keptWhole = view.laidOutWhole && abs(view.frame.height - wholeHeight) <= 0.5
    claim("c", view.layoutSteps == steps + 1 && moved > 1_000 && keptWhole,
        "a tick on token 18000: steps +\(view.layoutSteps - steps) (want 1), top \(f1(moved)), "
            + "height \(f1(view.frame.height)) (reference \(f1(wholeHeight)))")
    // (b) the last words with the view's bottom at the visible bottom.
    view.scrollToToken(26_999)
    spin(0.1)
    let bottom = clipTop(view)
    let atBottom = abs(view.visibleRect.maxY - view.frame.height) <= 0.5
    steps = view.layoutSteps
    view.setHighlight(26_999, follow: true)
    view.setHighlight(26_998, follow: true)
    claim("b", atBottom && view.laidOutWhole && view.layoutSteps == steps && clipTop(view) == bottom,
        "at the bottom \(atBottom) (top \(f1(bottom)) of \(f1(view.frame.height))): two ticks on "
            + "tokens 26999, 26998: steps +\(view.layoutSteps - steps) (want 0), top \(f1(clipTop(view)))")
    window.orderOut(nil)
    // (d) the bottom of a view not laid out whole is no end of the text. No
    // scroll rests there (the viewport's pass always lays out some 380 pt
    // below, measured), so the frame is cut to the visible bottom by hand.
    do {
        let (window, view, _) = longView()
        view.setFrameSize(NSSize(width: view.frame.width, height: view.visibleRect.maxY))
        let cut = abs(view.visibleRect.maxY - view.frame.height) <= 0.5 && !view.laidOutWhole
        steps = view.layoutSteps
        view.setHighlight(26_999, follow: true)
        let rect = view.rects(forToken: 26_999).first ?? .zero
        let shown = view.visibleRect
        let seen = rect.height > 0 && rect.minY >= shown.minY && rect.maxY <= shown.maxY
        claim("d", cut && view.layoutSteps == steps + 1 && seen,
            "not whole, the frame cut to the visible bottom \(cut): a tick on the last token: "
                + "steps +\(view.layoutSteps - steps) (want 1), in sight \(seen)")
        window.orderOut(nil)
    }
    row("F15", pass, detail)
}

do {
    var pass = true
    var detail = ""
    func claim(_ letter: String, _ ok: Bool, _ text: String) {
        pass = pass && ok
        detail += "(\(letter)) \(ok ? "ok" : "FAIL") \(text). "
    }
    let reference = referenceView()
    let refHeight = reference.view.frame.height
    let refY = reference.view.rects(forToken: 18_000).first?.minY ?? -1
    // (g5)'s: a word of paragraph 600 that starts a line at 304 pt and not at 322 pt.
    func lineStarts(_ shown: TranscriptView) -> Set<Int> {
        var starts: Set<Int> = []
        var lastY: CGFloat = -1
        for token in 18_000..<18_030 {
            guard let y = shown.rects(forToken: token).first?.minY, y > lastY + 0.5 else { continue }
            starts.insert(token)
            lastY = y
        }
        return starts
    }
    let narrowRef = referenceView(width: 322)
    let midWord = lineStarts(reference.view).subtracting(lineStarts(narrowRef.view))
        .filter { $0 > 18_000 }.min() ?? -1
    let midRefY = reference.view.rects(forToken: max(midWord, 0)).first?.minY ?? -1
    narrowRef.window.orderOut(nil)
    reference.window.orderOut(nil)
    let edited = referenceView(without: 5)
    let editedY = edited.view.rects(forToken: 17_999).first?.minY ?? -1
    let editedY9 = edited.view.rects(forToken: 8_999).first?.minY ?? -1
    let editedFar = edited.view.rects(forToken: 26_000).first?.minY ?? -1
    let editedHeight = edited.view.frame.height
    edited.window.orderOut(nil)
    // (g)'s: the same words in a window 340 pt wide, laid out from the top.
    let wideRef = referenceView(width: 340)
    let wideRefHeight = wideRef.view.frame.height
    let wideRefY = wideRef.view.rects(forToken: 18_000).first?.minY ?? -1
    let wideRefY9 = wideRef.view.rects(forToken: 9_000).first?.minY ?? -1
    wideRef.window.orderOut(nil)
    let full = TranscriptTokens.build(longWords(), pauses: [:])
    let less = TranscriptTokens.build(longWords(without: 5), pauses: [:])
    // (h)'s: all the words in the legacy scroll view, its scroller shown, laid out from the top.
    let legacyRef = legacyView(idle: false)
    legacyRef.view.show(full, fps: fps30, timecodeFrames: true)
    spin(0.2)
    legacyRef.view.layoutManager.ensureLayout(for: legacyRef.view.layoutManager.documentRange)
    legacyRef.view.layoutViewport()
    let legacyRefWidth = legacyRef.view.frame.width
    let legacyRefHeight = legacyRef.view.frame.height
    let legacyRefY = legacyRef.view.rects(forToken: 18_000).first?.minY ?? -1
    legacyRef.window.orderOut(nil)

    // What one pass costs: five fresh views, then five rebuilds at word 18,000
    // on the last of them (the pass called by hand, the idle one off).
    var fresh: [Double] = []
    var again: [Double] = []
    var added = 0.0
    for n in 0..<5 {
        let timed = longView(settle: 0)
        let before = footprintMB()
        var began = Date()
        timed.view.layOutAll()
        fresh.append(Date().timeIntervalSince(began))
        if n == 0 { added = footprintMB() - before }
        if n == 4 {
            timed.view.scrollToToken(18_000)
            for turn in 0..<5 {
                timed.view.show(turn % 2 == 0 ? less : full, fps: fps30, timecodeFrames: true)
                began = Date()
                timed.view.layOutAll()
                again.append(Date().timeIntervalSince(began))
            }
        }
        timed.window.orderOut(nil)
    }
    fresh.sort()
    again.sort()

    // (a) not in the rebuild, then once.
    let (window, view, _) = longView(idle: true, settle: 0)
    let clipHeight = view.enclosingScrollView?.contentView.bounds.height ?? 0
    let earlyPasses = view.wholeLayouts
    let early = earlyPasses == 0 && !view.laidOutWhole && view.frame.height < refHeight - 1
    let earlyHeight = view.frame.height
    settleWhole(view)
    claim("a", early && view.wholeLayouts == 1 && view.laidOutWhole
            && abs(view.frame.height - refHeight) <= 0.5,
        "as show returned: passes \(earlyPasses) (want 0), height \(f1(earlyHeight)); after a "
            + "turn: passes \(view.wholeLayouts) (want 1), height \(f1(view.frame.height)) "
            + "(reference \(f1(refHeight)))")
    // (b) the knob at word 18,000.
    view.scrollToToken(18_000)
    let top = clipTop(view)
    let knob = view.enclosingScrollView?.verticalScroller?.doubleValue ?? -1
    let knobWant = Double((refY - 4) / max(refHeight - clipHeight, 1))
    claim("b", abs(top - (refY - 4)) <= 0.5 && abs(knob - knobWant) <= 0.001,
        "word 18000: top \(f1(top)) (reference \(f1(refY - 4))), knob "
            + "\(String(format: "%.4f", knob)) (want \(String(format: "%.4f", knobWant)))")
    spin(0.1)
    // (c) a rebuild there keeps the top word's offset.
    func topWord(in other: TranscriptView? = nil)
        -> (id: TimelineTranscript.Identity?, offset: CGFloat, y: CGFloat)
    {
        let shown = other ?? view
        guard let index = shown.topVisibleToken(), let rect = shown.rects(forToken: index).first
        else { return (nil, -1, -1) }
        return (shown.model.tokens[index].word.id, rect.minY - shown.visibleRect.minY, rect.minY)
    }
    let was = topWord()
    var passes = view.wholeLayouts
    view.show(less, fps: fps30, timecodeFrames: true)
    let rebuilt = topWord()
    // As the pane's highlight does straight after a rebuild: far words measured
    // where estimates put them, before the pass.
    let farEstimate = view.rects(forToken: 26_000).first?.minY ?? -1
    _ = view.rects(forToken: 3_000)
    settleWhole(view)
    let now = topWord()
    let farNow = view.rects(forToken: 26_000).first?.minY ?? -1
    claim("c", was.id != nil && now.id == was.id && abs(now.offset - was.offset) <= 0.5
            && abs(now.y - editedY) <= 0.5 && view.wholeLayouts == passes + 1
            && abs(farNow - editedFar) <= 0.5 && abs(view.frame.height - editedHeight) <= 0.5,
        "a rebuild at word 18000: the same top word \(now.id == was.id), its offset "
            + "\(f1(was.offset)) → \(f1(rebuilt.offset)) as show returned → \(f1(now.offset)) "
            + "after the pass, at \(f1(now.y)) (reference \(f1(editedY))); token 26000, "
            + "measured before the pass at \(f1(farEstimate)), then at \(f1(farNow)) (reference "
            + "\(f1(editedFar))); height \(f1(view.frame.height)) (reference \(f1(editedHeight)))")
    // (d) two rebuilds in one turn cost one pass.
    passes = view.wholeLayouts
    view.show(full, fps: fps30, timecodeFrames: true)
    view.show(less, fps: fps30, timecodeFrames: true)
    settleWhole(view)
    spin(0.2)
    claim("d", view.wholeLayouts == passes + 1,
        "two rebuilds with no turn between: passes +\(view.wholeLayouts - passes) (want 1)")
    // (f) a scroll between the rebuild and its pass wins.
    view.show(full, fps: fps30, timecodeFrames: true)
    view.show(less, fps: fps30, timecodeFrames: true)
    view.scrollToToken(8_999)  // a paragraph's first word
    settleWhole(view)
    let far = topWord()
    claim("f", view.topVisibleToken() == 8_999 && abs(far.offset - 4) <= 0.5
            && abs(far.y - editedY9) <= 0.5,
        "a scroll to token 8999 before the pass: top token \(view.topVisibleToken() ?? -1), offset "
            + "\(f1(far.offset)) (want 4), at \(f1(far.y)) (reference \(f1(editedY9)))")
    // (e) a width change, alone and straight after a rebuild.
    passes = view.wholeLayouts
    window.setContentSize(NSSize(width: 340, height: 600))
    let short = !view.laidOutWhole
    settleWhole(view)
    let wide = view.laidOutWhole && view.wholeLayouts == passes + 1
    view.scrollToToken(18_000)
    spin(0.1)
    let held = topWord()
    view.show(full, fps: fps30, timecodeFrames: true)
    window.setContentSize(NSSize(width: 304, height: 600))
    settleWhole(view)
    let kept = topWord()
    claim("e", short && wide && held.id != nil && kept.id == held.id
            && abs(kept.offset - held.offset) <= 0.5 && abs(view.frame.height - refHeight) <= 0.5,
        "width 304 → 340: whole straight after \(!short) (want false), after a turn \(wide); a "
            + "rebuild then 340 → 304 with no turn between: the same top word \(kept.id == held.id), "
            + "offset \(f1(held.offset)) → \(f1(kept.offset)), height \(f1(view.frame.height)) "
            + "(reference \(f1(refHeight)))")
    func ms(_ seconds: Double) -> String { String(format: "%.0f", seconds * 1000) }
    // (g) a width change with no rebuild pending keeps the top word (#593): word 18,000 at
    // the top of the whole text, no anchor waiting.
    view.scrollToToken(18_000)
    spin(0.1)
    let start = topWord()
    let quiet = view.laidOutWhole && view.wholeLayoutAnchor == nil && view.topVisibleToken() == 18_000
    // (g1) 304 → 340 alone: straight after, before any turn, the word is in sight at its
    // offset (the arm's own restore; the pass would put a wrong one right afterwards).
    passes = view.wholeLayouts
    let resizing = Date()
    window.setContentSize(NSSize(width: 340, height: 600))
    let resizeTook = Date().timeIntervalSince(resizing)
    let straight = view.rects(forToken: 18_000).first ?? .zero
    let straightShown = view.visibleRect
    let straightIn = straight.height > 0 && straight.minY >= straightShown.minY
        && straight.maxY <= straightShown.maxY
    claim("g1", quiet && start.id != nil && straightIn
            && abs(straight.minY - straightShown.minY - start.offset) <= 0.5,
        "word 18000 at the top, whole, no anchor waiting \(quiet); width 304 → 340 in "
            + "\(String(format: "%.1f", resizeTook * 1000)) ms: straight after, its line at "
            + "\(f1(straight.minY)) in visible \(f1(straightShown.minY))…\(f1(straightShown.maxY)) "
            + "(offset \(f1(straight.minY - straightShown.minY)), was \(f1(start.offset))), in "
            + "sight \(straightIn)")
    // (g2) after the turn: the same word at its offset, where a layout at 340 pt puts it.
    settleWhole(view)
    let alone = topWord()
    claim("g2", alone.id == start.id && abs(alone.offset - start.offset) <= 0.5
            && abs(alone.y - wideRefY) <= 0.5 && abs(view.frame.height - wideRefHeight) <= 0.5
            && view.wholeLayouts == passes + 1,
        "after a turn: the same top word \(alone.id == start.id), offset \(f1(start.offset)) → "
            + "\(f1(alone.offset)), at \(f1(alone.y)) (reference \(f1(wideRefY))), height "
            + "\(f1(view.frame.height)) (reference \(f1(wideRefHeight))), passes "
            + "+\(view.wholeLayouts - passes) (want 1)")
    // (g3) a drag's steps, 340 → 322 → 304 with no turn between, the word at its offset
    // straight after each (no pass runs inside a drag), then one turn.
    passes = view.wholeLayouts
    window.setContentSize(NSSize(width: 322, height: 600))
    let midStep = topWord()
    window.setContentSize(NSSize(width: 304, height: 600))
    let lastStep = topWord()
    settleWhole(view)
    let dragged = topWord()
    claim("g3", midStep.id == start.id && abs(midStep.offset - start.offset) <= 0.5
            && lastStep.id == start.id && abs(lastStep.offset - start.offset) <= 0.5
            && dragged.id == start.id && abs(dragged.offset - start.offset) <= 0.5
            && abs(dragged.y - refY) <= 0.5 && abs(view.frame.height - refHeight) <= 0.5
            && view.wholeLayouts == passes + 1,
        "340 → 322 → 304 with no turn between: at 322 the top word the same "
            + "\(midStep.id == start.id) at offset \(f1(midStep.offset)), at 304 the same "
            + "\(lastStep.id == start.id) at offset \(f1(lastStep.offset)) (want "
            + "\(f1(start.offset)) at both); after a turn the same "
            + "\(dragged.id == start.id), offset \(f1(start.offset)) → \(f1(dragged.offset)), at "
            + "\(f1(dragged.y)) (reference \(f1(refY))), height \(f1(view.frame.height)) "
            + "(reference \(f1(refHeight))), passes +\(view.wholeLayouts - passes) (want 1)")
    // (g4) a scroll between the width change and its pass wins.
    window.setContentSize(NSSize(width: 340, height: 600))
    view.scrollToToken(9_000)  // a paragraph's first word
    settleWhole(view)
    let scrolled = topWord()
    claim("g4", view.topVisibleToken() == 9_000 && abs(scrolled.offset - 4) <= 0.5
            && abs(scrolled.y - wideRefY9) <= 0.5,
        "304 → 340, then a scroll to token 9000 before the pass: top token "
            + "\(view.topVisibleToken() ?? -1), offset \(f1(scrolled.offset)) (want 4), at "
            + "\(f1(scrolled.y)) (reference \(f1(wideRefY9)))")
    window.setContentSize(NSSize(width: 304, height: 600))
    settleWhole(view)
    // (g5) a drag from a word that starts a line at 304 pt and not at 322 pt: at the second
    // step the word at the top is another one, so only the first step's anchor keeps it. Its
    // line goes to the very top: at 4 pt the line above still holds the visible top's first
    // point, so that line's first word would be the top word.
    view.scrollToToken(midWord)
    view.scroll(to: view.rects(forToken: max(midWord, 0)).first?.minY ?? 0)
    spin(0.1)
    let midStart = topWord()
    let midTop = view.topVisibleToken()
    passes = view.wholeLayouts
    var stepTimes: [Double] = []
    for width in [322.0, 304.0] {
        let stepping = Date()
        window.setContentSize(NSSize(width: width, height: 600))
        stepTimes.append(Date().timeIntervalSince(stepping))
    }
    settleWhole(view)
    let midEnd = topWord()
    claim("g5", midWord > 18_000 && midTop == midWord && view.topVisibleToken() == midWord
            && abs(midEnd.offset - midStart.offset) <= 0.5 && abs(midEnd.y - midRefY) <= 0.5
            && abs(view.frame.height - refHeight) <= 0.5 && view.wholeLayouts == passes + 1,
        "token \(midWord) starts a line at 304 pt and not at 322 pt, at the top "
            + "\(midTop == midWord); 304 → 322 → 304 with no turn between (steps "
            + "\(stepTimes.map { String(format: "%.1f", $0 * 1000) }.joined(separator: ", ")) ms): "
            + "top token \(view.topVisibleToken() ?? -1), offset \(f1(midStart.offset)) → "
            + "\(f1(midEnd.offset)), at \(f1(midEnd.y)) (reference \(f1(midRefY))), height "
            + "\(f1(view.frame.height)) (reference \(f1(refHeight))), passes "
            + "+\(view.wholeLayouts - passes) (want 1)")
    // (h) a width change inside a rebuild: in the legacy scroll view a rebuild from words
    // 18,000–18,009 (shorter than the clip, the scroller hidden) to all 27,000 shows the
    // scroller, so the arm runs inside `show`, whose anchor must win. Measured on the word's
    // own line (the top visible token there is the paragraph above's).
    do {
        let narrow = legacyView(idle: true)
        narrow.view.show(
            TranscriptTokens.build(Array(longWords()[18_000..<18_010]), pauses: [:]),
            fps: fps30, timecodeFrames: true)
        settleWhole(narrow.view)
        let fewWidth = narrow.view.frame.width
        let fewTop = narrow.view.topVisibleToken()
        let fewY = narrow.view.rects(forToken: 0).first?.minY ?? -1
        let before = narrow.view.wholeLayouts
        narrow.view.show(full, fps: fps30, timecodeFrames: true)
        let grownWidth = narrow.view.frame.width
        func offset18() -> CGFloat {
            (narrow.view.rects(forToken: 18_000).first?.minY ?? -1) - narrow.view.visibleRect.minY
        }
        let returned = offset18()
        settleWhole(narrow.view)
        let grownY = narrow.view.rects(forToken: 18_000).first?.minY ?? -1
        let grown = offset18()
        claim("h", fewTop == 0 && fewWidth > grownWidth + 0.5
                && abs(grownWidth - legacyRefWidth) <= 0.5 && abs(grown - fewY) <= 0.5
                && abs(grownY - legacyRefY) <= 0.5
                && abs(narrow.view.frame.height - legacyRefHeight) <= 0.5
                && narrow.view.laidOutWhole && narrow.view.wholeLayouts == before + 1,
            "width \(f1(fewWidth)) with ten words, the first at the top \(fewTop == 0) at "
                + "\(f1(fewY)); \(f1(grownWidth)) as show returned with 27,000 (reference "
                + "\(f1(legacyRefWidth))); word 18000's offset \(f1(returned)) as show returned, "
                + "\(f1(grown)) after a turn (want \(f1(fewY))), at \(f1(grownY)) (reference "
                + "\(f1(legacyRefY))), height \(f1(narrow.view.frame.height)) (reference "
                + "\(f1(legacyRefHeight))), passes +\(narrow.view.wholeLayouts - before) (want 1)")
        narrow.window.orderOut(nil)
    }
    detail += "One pass over 27,000 words: fresh, median \(ms(fresh[2])) ms (\(ms(fresh[0]))–"
        + "\(ms(fresh[4]))); after a rebuild at word 18000, median \(ms(again[2])) ms "
        + "(\(ms(again[0]))–\(ms(again[4]))); \(String(format: "%.1f", added)) MB of footprint added."
    window.orderOut(nil)
    row("F16", pass, detail)
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

    // F17 ⌘Return selects the current match (TX-43).
    let commandReturn = { (flags: NSEvent.ModifierFlags) in key(36, "\r", window: window, flags: flags) }
    /// As `NSApplication` presses a ⌘ key: the window's key equivalents
    /// first, then, unclaimed, `sendEvent`.
    func pressLikeApp(_ flags: NSEvent.ModifierFlags) -> Bool {
        guard let event = commandReturn(flags) else { return false }
        if window.performKeyEquivalent(with: event) { return true }
        window.sendEvent(event)
        return false
    }
    func startOf(_ token: Int) -> Ticks {
        ReelTime.snapToFrame(model().tokens[token].word.start, fps: fps30)
    }
    func currentMatch() -> ClosedRange<Int>? {
        current().flatMap { pane.find.matches.indices.contains($0) ? pane.find.matches[$0].tokens : nil }
    }
    func fresh17(_ query: String?, playhead: Ticks = 0) {
        view.select(nil)
        editor.setPlayhead(playhead)
        spin(0.2)
        window.makeFirstResponder(view)
        editor.findInTranscript(nil)
        spin(0.1)
        if let query { _ = typeText(query) }
    }
    func matchSelected(_ match: ClosedRange<Int>?) -> Bool {
        guard let match else { return false }
        return view.selection == match && document.playhead == startOf(match.lowerBound)
            && document.inOutRange != nil && window.firstResponder === view && pane.isFindOpen
            && !band.isHidden
    }
    func said(_ match: ClosedRange<Int>?) -> String {
        "match \(String(describing: match)), selection \(String(describing: view.selection)), "
            + "playhead \(document.playhead) (want \(match.map { startOf($0.lowerBound) } ?? -1)), "
            + "range \(document.inOutRange != nil), first responder \(who()), bar open \(pane.isFindOpen)"
    }
    if pane.isFindOpen { pane.closeFind() }
    view.scroll(to: 0)
    fresh17("cafe")
    send(returnKey([]))  // one on, so the current match is not the first
    spin(0.1)
    let matchA = currentMatch()
    let currentA = current()
    let countA = pane.find.matches.count
    let tookA = commandReturn(.command).map { window.performKeyEquivalent(with: $0) } ?? false
    spin(0.3)
    let a17 = tookA && matchA?.count == 1 && matchSelected(matchA) && current() == currentA
        && pane.find.matches.count == countA && countA == 6
    let saidA = "(a) key-equivalent door answered \(tookA): \(said(matchA)), current "
        + "\(String(describing: current())) (was \(String(describing: currentA))), \(pane.find.matches.count) "
        + "matches → \(a17)"

    fresh17(nil)  // the bar open already: the field takes the keys again
    send(returnKey([]))
    spin(0.1)
    let matchB = currentMatch()
    let currentB = current()
    send(commandReturn(.command))
    spin(0.3)
    let b17 = matchB != nil && matchB != matchA && matchSelected(matchB) && current() == currentB
    let saidB = "(b) sendEvent: \(said(matchB)) → \(b17)"

    fresh17("Café Noir")
    let matchC = currentMatch()
    _ = pressLikeApp(.command)
    spin(0.3)
    let c17 = matchC?.count == 2 && matchSelected(matchC)
    let saidC = "(c) “Café Noir”: \(said(matchC)) → \(c17)"

    fresh17("afé")
    let matchD = currentMatch()
    let partial = current().map { pane.find.matches[$0].pieces.map(\.range.length) } ?? []
    _ = pressLikeApp(.command)
    spin(0.3)
    let d17 = matchD?.count == 1 && partial == [3] && matchSelected(matchD)
    let saidD = "(d) “afé”, pieces \(partial): \(said(matchD)) → \(d17)"

    let heldE = startOf(300)
    fresh17("zzzz", playhead: heldE)
    let noneE = current() == nil && pane.find.matches.isEmpty
    _ = pressLikeApp(.command)
    spin(0.3)
    let e17 = noneE && view.selection == nil && document.inOutRange == nil
        && document.playhead == heldE && typing() && pane.isFindOpen
    let saidE = "(e) no match \(noneE): selection \(String(describing: view.selection)), range "
        + "\(document.inOutRange != nil), playhead \(document.playhead) (was \(heldE)), first responder "
        + "\(who()) → \(e17)"

    fresh17("cafe")
    let currentF = current()
    let heldF = document.playhead
    let tookF = commandReturn([.command, .shift]).map { window.performKeyEquivalent(with: $0) } ?? true
    send(commandReturn([.command, .shift]))
    spin(0.3)
    let f17 = currentF != nil && !tookF && view.selection == nil && document.inOutRange == nil
        && document.playhead == heldF && typing()
    let saidF = "(f) ⌘⇧Return: key-equivalent door answered \(tookF) (want false); selection "
        + "\(String(describing: view.selection)), range \(document.inOutRange != nil), playhead "
        + "\(document.playhead) (was \(heldF)), first responder \(who()), current "
        + "\(String(describing: currentF)) → \(String(describing: current())) → \(f17)"

    fresh17("cafe")
    let matchG = currentMatch()
    _ = pressLikeApp(.command)
    spin(0.3)
    let heldG = matchSelected(matchG)
    send(escape())
    spin(0.2)
    let clearedG = view.selection == nil && pane.isFindOpen
    send(escape())
    spin(0.2)
    let closedG = !pane.isFindOpen && window.firstResponder === view
    fresh17(nil)  // opens again on the kept text
    let matchG2 = currentMatch()
    _ = pressLikeApp(.command)
    spin(0.3)
    let heldG2 = matchSelected(matchG2)
    let tokensG = model().tokens.count
    let rebuildsG = pane.source.rebuilds
    send(key(51, "\u{7f}", window: window))
    _ = until(5) { pane.source.rebuilds != rebuildsG && pane.source.settled }
    spin(0.3)
    let stepG = document.undoManager?.undoActionName ?? ""
    let deletedG = stepG == "Delete Words" && model().tokens.count < tokensG
    let afterG = model().tokens.count
    if stepG == "Delete Words" {
        document.undoManager?.undo()
        _ = until(5) { pane.source.settled && pane.source.model.tokens.count == 800 }
        spin(0.3)
    }
    let g17 = heldG && clearedG && closedG && heldG2 && deletedG
    let saidG = "(g) selected \(heldG); Esc cleared, bar open \(clearedG); Esc closed it, the text "
        + "keeping the keys \(closedG); ⌘Return again \(heldG2), then ⌫: step “\(stepG)”, tokens "
        + "\(tokensG) → \(afterG) → \(g17)"
    row("F17", a17 && b17 && c17 && d17 && e17 && f17 && g17,
        [saidA, saidB, saidC, saidD, saidE, saidF, saidG].joined(separator: "; "))
    if pane.isFindOpen { pane.closeFind() }
    view.select(nil)
    spin(0.2)

    // F18 Edit ▸ Find… on the Media tab (TX-45).
    func descendants(_ root: NSView) -> [NSView] { root.subviews + root.subviews.flatMap(descendants) }
    func mediaSearch() -> MediaSearchField? {
        descendants(inspector.view).compactMap { $0 as? MediaSearchField }.first { $0.window != nil }
    }
    func mediaRowsShown() -> Int {
        descendants(inspector.view).filter { $0 is MediaRowView && !$0.isHiddenOrHasHiddenAncestor }.count
    }
    func searchTyping(_ field: MediaSearchField?) -> Bool {
        guard let field, let text = window.firstResponder as? NSTextView else { return false }
        return text.delegate === field
    }
    var perTab: [String] = []
    var tabsRight = true
    let tabs18: [(String, InspectorTab, Bool)] = [
        ("Clip", .clip, false), ("Document", .document, false), ("Assistant", .assistant, false),
        ("Transcript", .transcript, true), ("Media", .media, true),
    ]
    for (name, tab, want) in tabs18 {
        inspector.select(tab)
        spin(0.3)
        let answer = editor.validateUserInterfaceItem(item)
        tabsRight = tabsRight && answer == want
        perTab.append("\(name) \(answer)")
    }
    let a18 = tabsRight
    let saidA18 = "(a) the validator: \(perTab.joined(separator: ", ")) (want false, false, false, "
        + "true, true) → \(a18)"

    let search = mediaSearch()
    let name = document.project.snapshot.media.first?.name ?? ""
    let prefix = String(name.prefix(3))
    if let search { window.makeFirstResponder(search) }
    spin(0.1)
    _ = typeText(prefix)
    window.makeFirstResponder(root)
    spin(0.1)
    editor.findInTranscript(nil)
    spin(0.2)
    let editorB = window.firstResponder as? NSTextView
    let rangeB = editorB?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
    let whole = NSRange(location: 0, length: (prefix as NSString).length)
    // Pressed again with the caret at the end: the whole text selected again.
    editorB?.setSelectedRange(NSRange(location: whole.length, length: 0))
    editor.findInTranscript(nil)
    spin(0.2)
    let againB = (window.firstResponder as? NSTextView)?.selectedRange()
    let b18 = search != nil && !prefix.isEmpty && searchTyping(search) && search?.stringValue == prefix
        && rangeB == whole && againB == whole
    let saidB18 = "(b) “\(prefix)” typed and the keys handed back; the action: field typing "
        + "\(searchTyping(search)), selected \(rangeB) of “\(search?.stringValue ?? "no field")”; "
        + "again from the caret at the end: \(String(describing: againB)) → \(b18)"

    let shownBefore = mediaRowsShown()
    _ = typeText("zzzz")
    let shownNone = mediaRowsShown()
    _ = typeText(prefix)
    let shownAgain = mediaRowsShown()
    let c18 = shownBefore == 1 && shownNone == 0 && shownAgain == 1
    let saidC18 = "(c) rows shown \(shownBefore), “zzzz” \(shownNone), “\(prefix)” \(shownAgain) "
        + "(want 1, 0, 1) → \(c18)"

    send(returnKey([]))
    spin(0.2)
    let backD = window.firstResponder === root
    send(key(49, " ", window: window))
    let playedD = until(2) { editor.playback.isPlaying }
    editor.playback.pause()
    _ = until(2) { !editor.playback.isPlaying }
    let d18 = backD && playedD
    let saidD18 = "(d) Return: first responder \(who()) (want the content view), Space played "
        + "\(playedD) → \(d18)"

    let shutKey = InspectorSection.collapsedKeyPrefix + "media.files"
    let defaults = UserDefaults.standard
    let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    let shutDomain: [String: Any] = [shutKey: true]
    defaults.setVolatileDomain(
        arguments.merging(shutDomain) { $1 }, forName: UserDefaults.argumentDomain)
    inspector.select(.clip)
    inspector.select(.media)
    spin(0.3)
    let shutField = descendants(inspector.view).compactMap { $0 as? MediaSearchField }.first
    let shut = shutField?.isHiddenOrHasHiddenAncestor == true
    let validShut = editor.validateUserInterfaceItem(item)
    window.makeFirstResponder(root)
    editor.findInTranscript(nil)
    spin(0.2)
    let stayedShut = window.firstResponder === root
    defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    inspector.select(.clip)
    inspector.select(.media)
    spin(0.3)
    let reopened = editor.validateUserInterfaceItem(item)
    let e18 = shut && !validShut && stayedShut && reopened
    let saidE18 = "(e) section shut \(shut): validator \(validShut) (want false), keys left with "
        + "the content view \(stayedShut); opened again: validator \(reopened) → \(e18)"

    editor.inspectorContainer.isHidden = true
    spin(0.2)
    let validHidden = editor.validateUserInterfaceItem(item)
    window.makeFirstResponder(root)
    editor.findInTranscript(nil)
    spin(0.2)
    let stayedHidden = window.firstResponder === root
    editor.inspectorContainer.isHidden = false
    spin(0.3)
    let shownAgainF = editor.validateUserInterfaceItem(item)
    let f18 = !validHidden && stayedHidden && shownAgainF
    let saidF18 = "(f) inspector hidden: validator \(validHidden) (want false), keys left with the "
        + "content view \(stayedHidden); shown again: validator \(shownAgainF) → \(f18)"

    var g18 = false
    var saidG18 = "(g) no field or scroll view"
    if let field = mediaSearch(), let scroll = field.enclosingScrollView, let paneView = scroll.documentView {
        let tall = paneView.heightAnchor.constraint(greaterThanOrEqualToConstant: 3000)
        tall.isActive = true
        spin(0.2)
        window.layoutIfNeeded()
        let foot = max(0, paneView.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: foot))
        scroll.reflectScrolledClipView(scroll.contentView)
        spin(0.1)
        func inSight() -> Bool {
            let rect = field.convert(field.bounds, to: scroll.contentView)
            return scroll.contentView.bounds.contains(rect)
        }
        let hiddenBefore = !inSight()
        window.makeFirstResponder(root)
        editor.findInTranscript(nil)
        spin(0.2)
        let shownAfter = inSight()
        let typingG = searchTyping(field)
        g18 = hiddenBefore && shownAfter && typingG
        saidG18 = "(g) the pane \(paneView.frame.height) pt tall in \(scroll.contentView.bounds.height); "
            + "the field out of sight \(hiddenBefore) at clip y \(foot); the action: in sight "
            + "\(shownAfter) at clip y \(scroll.contentView.bounds.minY), typing \(typingG) → \(g18)"
        tall.isActive = false
        _ = typeText("")
        window.makeFirstResponder(root)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        spin(0.2)
    }
    row("F18", a18 && b18 && c18 && d18 && e18 && f18 && g18,
        [saidA18, saidB18, saidC18, saidD18, saidE18, saidF18, saidG18].joined(separator: "; "))
    inspector.select(.transcript)
    document.close()
} else {
    for id in ["F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F12", "F17", "F18"] {
        row(id, false, "the editor did not open on \(package)")
    }
}

if let data = try? JSONSerialization.data(withJSONObject: ["rows": rows]),
    let text = String(data: data, encoding: .utf8)
{
    print(text)
}
exit(0)
