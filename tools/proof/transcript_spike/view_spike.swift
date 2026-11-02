// Road map "creator-jobs" TX2a, spike TX-S2 — the view. Built AS `main.swift`
// over `app/Sources` (`view_spike.py`, through `swift_build.build`, -O), it
// measures candidate (b), `TranscriptView` itself, in a 304 × 800 pt scroll
// view in an offscreen window on the main thread, Source Sans 3 registered.
//
//   view-spike <fonts folder> <answer.json> [<png>]
//
// The input is a synthetic `TranscriptTokens`: 27,000 words of 3–9 letters in
// 900 paragraphs on two tracks, 40 with `collapsedBefore`, 300 `struck`, 10 %
// not editable with a `why`. Each timing is a median of 20 (milliseconds):
// the first layout and draw of the visible part (a fresh view each run); a
// rebuild with one word removed, the anchor kept; a highlight move to the
// adjacent word and to one 5,000 words away (moved, then the dirty rects
// drawn); `tokenIndex(at:)`; a selection across three paragraphs, drawn; and
// the added `phys_footprint`. Key rows: the view is not an `NSText`;
// `SpaceKey.route` answers `.transport` with it first responder; J, K and L
// sent through `window.sendEvent` reach a recording sink set as the
// `nextResponder` of an ancestor.
import AppKit

let args = CommandLine.arguments
let fonts = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let png = args.count > 3 ? URL(fileURLWithPath: args[3]) : nil

if let names = try? FileManager.default.contentsOfDirectory(atPath: fonts.path) {
    for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
        CTFontManagerRegisterFontsForURL(fonts.appendingPathComponent(name) as CFURL, .process, nil)
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

func ms(_ body: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return .nan }
    let mid = sorted.count / 2
    return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

// MARK: - The fixture

struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
var random = Seeded(state: 0x5EED)
let letters = Array("abcdefghijklmnopqrstuvwxyz")
let second = ReelTime.perSecond
var words: [TimelineTranscript.Word] = []
var t: Ticks = 0
for paragraph in 0..<900 {
    let track: UInt32 = paragraph % 2 == 0 ? 1 : 2
    for _ in 0..<30 {
        let length = Int.random(in: 3...9, using: &random)
        let text = String((0..<length).map { _ in letters[Int.random(in: 0..<26, using: &random)] })
        let editable = Int.random(in: 0..<10, using: &random) != 0
        words.append(
            TimelineTranscript.Word(
                text: text, start: t, end: t + second / 4, clip: UInt32(paragraph / 30 + 1),
                track: track, media: 1, engine: .apple, filler: false, speaker: nil,
                editable: editable,
                why: editable ? nil : "Under a transition: a cut here would leave one clip's tail "
                    + "under its neighbour.",
                id: TimelineTranscript.Identity(nestPath: [], media: 1, source: t, k: 0)))
        t += second * 3 / 10
    }
    t += second * 2
}
var struck = Set<Int>()
while struck.count < 300 { struck.insert(Int.random(in: 0..<words.count, using: &random)) }
var collapsed: [Int: Int] = [:]
while collapsed.count < 40 { collapsed[Int.random(in: 1..<words.count, using: &random)] = 3 }
let tokens = TranscriptTokens.build(words, pauses: [:], struck: struck, collapsed: collapsed)
let fps = Fps(num: 30, den: 1)

// MARK: - The window

let window = NSWindow(
    contentRect: NSRect(x: -20_000, y: 0, width: 304, height: 800), styleMask: [.titled],
    backing: .buffered, defer: false)
final class Sink: NSResponder {
    var keys: [String] = []
    override func keyDown(with event: NSEvent) { keys.append(event.charactersIgnoringModifiers ?? "") }
}
let sink = Sink()
let container = NSView(frame: NSRect(x: 0, y: 0, width: 304, height: 800))
window.contentView = container
window.appearance = NSAppearance(named: .aqua)  // the capture's look, as the harness pins it
window.orderFrontRegardless()

func makeScroll() -> (NSScrollView, TranscriptView) {
    let scroll = NSScrollView(frame: container.bounds)
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 800))
    view.autoresizingMask = [.width]
    scroll.documentView = view
    for old in container.subviews { old.removeFromSuperview() }
    container.addSubview(scroll)
    return (scroll, view)
}

func draw(_ scroll: NSScrollView) {
    scroll.layoutSubtreeIfNeeded()
    scroll.displayIfNeeded()
}

var rows: [[String: Any]] = []
var timings: [String: Any] = [:]

// First layout and draw of the visible part, a fresh view each run.
let before = footprint()
var first: [Double] = []
var kept: (NSScrollView, TranscriptView)!
for run in 0..<20 {
    let made = makeScroll()
    first.append(ms {
        made.1.show(tokens, fps: fps, timecodeFrames: true)
        made.0.needsDisplay = true
        draw(made.0)
    })
    if run == 0 { kept = made }
}
let (scroll, view) = makeScroll()
view.show(tokens, fps: fps, timecodeFrames: true)
draw(scroll)
let added = Int64(footprint()) - Int64(before)
_ = kept
timings["first_layout_ms"] = median(first)
timings["first_layout_all_ms"] = first

// A rebuild with one word removed, the anchor kept.
view.scrollToToken(13_500)
draw(scroll)
var rebuild: [Double] = []
var anchorKept = true
var current = tokens
for run in 0..<20 {
    let topBefore = view.topVisibleToken().map { current.tokens[$0].word.id }
    var fewer = Array(current.tokens.map(\.word))
    fewer.remove(at: 13_600 + run)
    let next = TranscriptTokens.build(fewer, pauses: [:])
    rebuild.append(ms {
        view.show(next, fps: fps, timecodeFrames: true)
        draw(scroll)
    })
    current = next
    let topAfter = view.topVisibleToken().map { current.tokens[$0].word.id }
    if topBefore != topAfter { anchorKept = false }
}
timings["rebuild_ms"] = median(rebuild)
timings["rebuild_anchor_kept"] = anchorKept

// The highlight: to the adjacent word, then 5,000 away.
guard let top = view.topVisibleToken() else { fatalError("no visible token") }
var adjacent: [Double] = []
var far: [Double] = []
for run in 0..<20 {
    view.setHighlight(top + run % 4, follow: false)
    draw(scroll)
    adjacent.append(ms {
        view.setHighlight(top + run % 4 + 1, follow: false)
        draw(scroll)
    })
    far.append(ms {
        view.setHighlight(top + 5_000 + run, follow: false)
        draw(scroll)
    })
}
timings["highlight_adjacent_ms"] = median(adjacent)
timings["highlight_far_ms"] = median(far)

// Hit-testing a click.
let firstRect = view.rects(forToken: top + 2).first ?? .zero
let point = NSPoint(x: firstRect.midX, y: firstRect.midY)
var hits: [Double] = []
var hitIndex: Int?
for _ in 0..<20 { hits.append(ms { hitIndex = view.tokenIndex(at: point) }) }
timings["hit_test_ms"] = median(hits)
timings["hit_test_token"] = hitIndex ?? -1
timings["hit_test_expected"] = top + 2

// A selection across three paragraphs, drawn.
let paragraph = current.tokens[top].paragraph
let lastOf = current.paragraphs[min(paragraph + 2, current.paragraphs.count - 1)].endToken - 1
var selections: [Double] = []
for run in 0..<20 {
    view.select(nil)
    draw(scroll)
    selections.append(ms {
        view.select(current.paragraphs[paragraph].firstToken...(lastOf - run % 2))
        draw(scroll)
    })
}
timings["selection_ms"] = median(selections)
timings["added_footprint_bytes"] = added
timings["physical_memory"] = Int64(ProcessInfo.processInfo.physicalMemory)
timings["paragraphs"] = current.paragraphs.count
timings["tokens"] = tokens.tokens.count
timings["document_height"] = view.frame.height
timings["fragments"] = view.fragments.count
timings["first_fragment"] = view.fragments.first.map { "\($0.layoutFragmentFrame) \($0.textLineFragments.count)" } ?? "none"
timings["visible"] = "\(view.visibleRect)"

// The keys.
rows.append(["name": "not NSText", "ok": !((view as NSView) is NSText)])
let space = NSEvent.keyEvent(
    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: window.windowNumber, context: nil, characters: " ",
    charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
window.makeFirstResponder(view)
let route = SpaceKey.route(space, firstResponder: window.firstResponder, sheetAttached: false)
rows.append([
    "name": "SpaceKey.route answers .transport with the view first responder",
    "ok": route == .transport && window.firstResponder === view, "detail": "\(String(describing: route))",
])
container.nextResponder = sink
for (code, letter) in [(UInt16(38), "j"), (UInt16(40), "k"), (UInt16(37), "l")] {
    if let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: letter,
        charactersIgnoringModifiers: letter, isARepeat: false, keyCode: code)
    {
        window.sendEvent(event)
    }
}
rows.append([
    "name": "J, K and L reach a sink beyond the view", "ok": sink.keys == ["j", "k", "l"],
    "detail": "\(sink.keys)",
])

if let png, let rep = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) {
    scroll.cacheDisplay(in: scroll.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: png)
}

let answer: [String: Any] = ["timings": timings, "rows": rows]
if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys]) {
    try? data.write(to: out)
}
exit(0)
