// tools/proof/harness/main.swift — the offscreen chrome harness.
//
// This is the program CLAUDE.md's "Seeing the chrome" section describes:
// every file in `app/Sources` except the app's own `main.swift` is compiled
// together with THIS file (`build.sh` has the swiftc line), linked against
// `core/target/release/libreelcut_core.a`, and the result opens a `.reelcut`
// package from disk through `ProjectDocument.read(from:ofType:)`, puts an
// `EditorViewController` in an `NSWindow`, spins the runloop a few turns and
// `cacheDisplay(in:to:)`s the content view into a PNG. That is the same paint
// path the window uses, it needs no Screen Recording grant (`screencapture`
// silently writes a black PNG without one), and it renders either appearance
// on demand. The preview well comes out black — a Metal layer has no drawable
// offscreen — which does not matter, because the chrome is the point.
//
// Selection, the playhead and the S/M/L size are VIEW state and are not in
// the package, so the arguments set them:
//
//   harness <project.reelcut|welcome> <out.png> <light|dark>
//           [w] [h] [selectIndex] [playheadSec] [sizeIndex 0-2] [clip|media|document]
//           [candidateSpans] [expandSections]
//
// `selectIndex` picks the clip at that index in START order (-1 for none).
// The PNG is written at the main screen's backing scale (2x on a Retina
// Mac: a 1440x862 window is a 2880x1724 image), 8-bit RGBA.
//
// The last two arguments were added for `tools/proof/phase3_chrome.py`, and
// they are the SAME kind of thing as `selectIndex` and `playheadSec`: view
// state a package cannot carry, so the render has to be told it. Both default
// to "-" (nothing), which is exactly what every earlier caller got, so a
// nine-argument invocation renders the bytes it always did.
//
//   `candidateSpans`   Remove Silences' candidate wash (road map 2 phase 3a):
//                      comma-separated `start-end` pairs in SECONDS, e.g.
//                      "1-2,6-7". The sheet is the only thing that sets
//                      `TimelineView.candidateSpans` in the app and a sheet
//                      cannot be put up offscreen, so without this the wash
//                      could not be photographed at all.
//   `expandSections`   comma-separated `InspectorSection` ids to open, e.g.
//                      "video.obscure". A section's collapsed state is a
//                      `UserDefaults` key this file already pins (it CLEARS
//                      them, so `defaultExpanded` decides), and a section
//                      built `defaultExpanded: false` therefore shows nothing
//                      but its header — its rows cannot be seen at all. Each
//                      id here pins its key to "not collapsed".
//
// A SECOND MODE, which renders nothing:
//
//   harness cues <words.json> <out.json>
//
// reads a word list and writes the cues `CaptionCues.build` makes of it. It
// belongs in this program and nowhere else, for one reason: this is the only
// binary in the tree that links `app/Sources` outside the app, and the four
// cue rules — at most two lines, at most 42 characters a line, at most six
// seconds a cue, at least a frame of gap between cues — cannot be reached any
// other way without a person at the machine. Nothing in the app calls
// `CaptionCues` until a recogniser has produced words, and
// `SFSpeechRecognizer` will not produce any without a Speech Recognition
// grant that only a frontmost app can be given, so over MCP those rules are
// unreachable and `phase4_proof.py` says so out loud rather than pretending
// otherwise. The arithmetic itself has no `Speech` in it at all — words with
// times in, cues out — so the way to test it is to hand it words with times,
// and this is the one place from which that can be done.
//
// It is a MODE and not a fifth render argument because it shares nothing with
// a render: no window, no pinned defaults, no fonts, no appearance. It is
// answered before any of that is set up, the way `welcome` is answered before
// a package is opened, and every render argument below keeps the position it
// had — `phase2_chrome.py`, `phase3_chrome.py` and `phase4_chrome.py` all
// depend on that order, so this file grows by addition and never by
// rearrangement.
//
// `words.json` is `{"fps": [30, 1], "words": [{"text": "…", "start": 0,
// "end": 300000}, …]}`, in TICKS rather than seconds, because the rules are
// measured in ticks and a frame at 30 fps is 20 000 of them and 0.0333… of a
// second: a fixture written in seconds could not say "exactly one frame"
// exactly. `fps` defaults to 30/1 and is what the gap is one frame OF. The
// output is `{"fps", "frame", "cues"}`, and each cue carries its `start`,
// `end`, `text` and `tag` plus `snapped_start` and `snapped_end` — those two
// times put on the frame grid by the same `ReelTime.snapToFrame` that
// `CaptionLayout.place` will call on them next, since the gap rule's whole
// point is that it is still there after the snap.
//
// Determinism: the app persists its pane sizes, the inspector's collapsed
// state, the track height, snapping and the Document tab's one checkbox in
// `UserDefaults`, and a bare binary shares the "harness" defaults domain
// with anything else called harness. So every key the CHROME reads — and
// AppKit's scroller-style switch — is pinned in the volatile ARGUMENT
// domain before the first view loads: that domain is searched first, and
// nothing the run writes back (`splitViewDidResizeSubviews` stores the pane
// sizes) can change the next run's answer. Two renders of one package are
// byte-identical; `tools/proof/phase2_chrome.py` checks that first. The
// keys the app reads and the chrome does NOT draw (`ReelcutCompositorTiming`,
// `RCFFmpegImport`, `RCFFmpegPath`) are left alone.
import AppKit
import CoreText

/// Offscreen render of the editor chrome. Screen capture needs a TCC grant this
/// process does not have, so the views are asked to draw themselves instead:
/// `cacheDisplay(in:to:)` is the same paint path the window uses, minus the
/// compositor's Metal layer (which has no drawable offscreen and comes out
/// empty — the chrome is what this is for).
enum Harness {
    static func registerFonts(_ directory: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for name in names where name.hasSuffix(".ttf") || name.hasSuffix(".otf") {
            CTFontManagerRegisterFontsForURL(
                directory.appendingPathComponent(name) as CFURL, .process, nil)
        }
    }

    /// The editor's persisted view state, pinned so a render never depends on
    /// what an earlier run (or another program sharing the defaults domain)
    /// left behind. The keys are `EditorViewController`'s, `InspectorPane`'s
    /// and `DocumentPane`'s; the values are the app's own defaults.
    static func pinDefaults(sizeIndex: Int, expand: [String]) {
        var pinned: [String: Any] = [
            "ReelcutInspectorWidth": 304.0,       // DS.panelWidth
            "ReelcutTimelineHeight": 300.0,       // EditorViewController.defaultTimelineHeight
            "ReelcutInspectorCollapsed": false,
            "ReelcutTimelineTrackHeight": sizeIndex,
            "ReelcutSnappingEnabled": true,
            "ReelcutSafeGuidesVisible": false,
            // The Document tab's "Resize clips proportionally" checkbox is
            // drawn from this key at paint time (`DocumentPane.rescaleClipsKey`),
            // so a `document` render moved with the machine's stored value
            // until it was pinned. `false` is `bool(forKey:)` of an absent key.
            "ReelcutInspectorRescaleClips": false,
            "AgentServerEnabled": false,
            // AppKit picks legacy (16 pt, always visible) or overlay scrollers
            // by whether a MOUSE is attached, and the inspector pane is 16 pt
            // narrower under the legacy kind, which moves its header's right
            // end. Pinned to the legacy kind so the same package renders the
            // same bytes on a laptop alone as on a desk. Measured: this key is
            // honoured from the argument domain — `WhenScrolling` changes the
            // render, `Always` and `Automatic`-with-a-mouse are identical.
            "AppleShowScrollBars": "Always",
        ]
        // `InspectorSection` stores COLLAPSED, so `false` is "open". The loop
        // below drops every such key from the persistent domain and the
        // argument domain is searched first, so these decide.
        for id in expand where !id.isEmpty {
            pinned[InspectorSection.collapsedKeyPrefix + id] = false
        }
        UserDefaults.standard.setVolatileDomain(pinned, forName: UserDefaults.argumentDomain)
        // A section's collapsed state is stored per section id; any such key
        // left in the persistent domain would re-collapse one section on one
        // machine. Drop them so `defaultExpanded` applies everywhere.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("ReelcutInspectorSection.") {
            defaults.removeObject(forKey: key)
        }
    }

    /// A comma-separated argument. "-" and "" both mean nothing, so an
    /// omitted argument and an explicit "no" are the same thing — every
    /// other argument here reads that way too.
    static func list(_ text: String) -> [String] {
        guard text != "-", !text.isEmpty else { return [] }
        return text.split(separator: ",").map { String($0) }
    }

    /// `list`'s entries as `start-end` pairs in SECONDS. A pair that is not
    /// two numbers is DROPPED rather than clamped: the caller is a proof
    /// script, and a silently mis-parsed span would show up as a missing
    /// wash, which is a failing check rather than a passing lie.
    static func spans(_ text: String) -> [SilenceDetector.Span] {
        list(text).compactMap { pair in
            let parts = pair.split(separator: "-")
            guard parts.count == 2, let from = Double(parts[0]), let to = Double(parts[1])
            else { return nil }
            return SilenceDetector.Span(
                start: Ticks(from * 600_000), end: Ticks(to * 600_000))
        }
    }

    /// The cue builder, run over a word list from a file — the second mode of
    /// the header, and the only way `CaptionCues.build` can be reached without
    /// a Speech Recognition grant.
    ///
    /// Everything here is a translation: JSON into `CaptionCues.Word`s, the
    /// cues back into JSON. Nothing is computed that the app does not compute,
    /// which is the point — a proof that re-implemented the rules in order to
    /// check them would be checking itself. The one addition is the pair of
    /// snapped times, and even those are `ReelTime.snapToFrame`'s over
    /// `CaptionLayout.place`'s own `max(0, start)`: they are the first thing
    /// the placement does to a cue, before it has had any say of its own about
    /// one shorter than a frame or one that overlaps its successor.
    static func cues(from input: URL, to output: URL) throws {
        struct Request: Decodable {
            struct Word: Decodable {
                let text: String
                let start: Ticks
                let end: Ticks
            }
            /// `[num, den]`, the model's own spelling of a rate (§5.2).
            let fps: [Int]?
            let words: [Word]
        }
        let request = try JSONDecoder().decode(Request.self, from: Data(contentsOf: input))
        let rate = request.fps ?? [30, 1]
        let fps = Fps(num: rate.first ?? 30, den: rate.count > 1 ? rate[1] : 1)
        // `max(_, 1)` is `CaptionLayout.place`'s own guard against a
        // degenerate rate, and the builder is handed the same number the
        // placement will use.
        let frame = max(fps.frameDuration, 1)
        let built = CaptionCues.build(
            from: request.words.map {
                CaptionCues.Word(text: $0.text, start: $0.start, end: $0.end)
            }, frame: frame)
        let rows = built.map { cue -> [String: Any] in
            [
                "start": cue.start,
                "end": cue.end,
                "snapped_start": ReelTime.snapToFrame(max(0, cue.start), fps: fps),
                "snapped_end": ReelTime.snapToFrame(cue.end, fps: fps),
                "text": cue.text,
                "tag": cue.tag,
            ]
        }
        let json: [String: Any] = ["fps": [fps.num, fps.den], "frame": frame, "cues": rows]
        try JSONSerialization
            .data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: output)
    }

    /// One capture of the view, as PNG bytes.
    private static func capture(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "harness", code: 1)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "harness", code: 2)
        }
        return data
    }

    /// Captures the view once it has STOPPED MOVING, rather than after a fixed
    /// number of runloop turns.
    ///
    /// A fixed spin count is a guess about how long the last relayout takes,
    /// and waiting for the answer is better than guessing at it whatever else
    /// is true.
    ///
    /// It is NOT, however, what makes a render reproducible, and the history
    /// is worth keeping so nobody re-reads it the same way. This was landed
    /// in phase 4 as the cure for a bistable inspector — the Actions pane
    /// sometimes at its intrinsic height and sometimes stretched, a render
    /// deterministic within a process and different across processes — and it
    /// cured nothing, because a settle can only wait out a layout that is
    /// still MOVING and both of those layouts had already stopped. The cause
    /// was an ambiguous constraint in `InspectorPane.swift` (a bottom pin at
    /// `.defaultLow` tying with a section's own default hugging of 250), and
    /// it is fixed there. Keep this loop for what it actually buys — no magic
    /// number to re-tune when a view is added — and do not reach for it again
    /// when two runs disagree: identical, stable, DIFFERENT output is an
    /// ambiguity to find, not a race to out-wait.
    ///
    /// So the instrument waits for its subject: capture, spin, capture again,
    /// and only write when two consecutive captures are byte-identical. A
    /// layout that has stopped changing produces the same bytes twice; one
    /// still settling does not. The bound is generous because the cost of an
    /// extra turn is milliseconds and the cost of a flaky proof is a person
    /// re-running it and learning to distrust it.
    static func png(_ view: NSView, to url: URL) throws {
        var previous = try capture(view)
        for _ in 0..<40 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
            let next = try capture(view)
            if next == previous {
                try next.write(to: url)
                return
            }
            previous = next
        }
        FileHandle.standardError.write(
            "warning: the layout never settled; writing the last capture\n".data(using: .utf8)!)
        try previous.write(to: url)
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write(
        ("usage: harness <project.reelcut|welcome> <out.png> <light|dark> "
            + "[w] [h] [selectIndex] [playheadSec] [sizeIndex 0-2] [clip|media|document] "
            + "[candidateSpans] [expandSections]\n"
            + "       harness cues <words.json> <out.json>\n")
            .data(using: .utf8)!)
    exit(64)
}

// The cue mode, answered first and answered here: it opens no package, wakes
// no AppKit and reads no defaults, so none of the setup below it applies. Its
// three arguments sit inside the render form's own count, so the guard above
// serves both and no render argument moved.
if arguments[1] == "cues" {
    do {
        try Harness.cues(
            from: URL(fileURLWithPath: arguments[2]), to: URL(fileURLWithPath: arguments[3]))
        print("wrote \(arguments[3])")
        exit(0)
    } catch {
        FileHandle.standardError.write("cues failed: \(error)\n".data(using: .utf8)!)
        exit(4)
    }
}

let projectURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])
let appearanceName: NSAppearance.Name = arguments[3] == "dark" ? .darkAqua : .aqua
let width = arguments.count > 4 ? Double(arguments[4]) ?? 1440 : 1440
let height = arguments.count > 5 ? Double(arguments[5]) ?? 862 : 862
/// Selection and the playhead are VIEW state and never reach the package, so
/// the render has to be told what to pick.
let selectIndex = arguments.count > 6 ? Int(arguments[6]) ?? -1 : -1
let playheadSeconds = arguments.count > 7 ? Double(arguments[7]) ?? 0 : 0
let sizeIndex = arguments.count > 8 ? min(max(Int(arguments[8]) ?? 1, 0), 2) : 1
let tabName = arguments.count > 9 ? arguments[9] : "clip"
/// Two more pieces of view state a package cannot carry — see the header.
let candidateSpans = Harness.spans(arguments.count > 10 ? arguments[10] : "-")
let expandSections = Harness.list(arguments.count > 11 ? arguments[11] : "-")

Harness.pinDefaults(sizeIndex: sizeIndex, expand: expandSections)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
NSApp.appearance = NSAppearance(named: appearanceName)
Harness.registerFonts(URL(fileURLWithPath: arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("Fonts"))

// "welcome" renders the no-document window instead of an editor.
if arguments[1] == "welcome" {
    WelcomeWindowController.shared.show()
    for _ in 0..<10 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    guard let root = WelcomeWindowController.shared.window?.contentView else { exit(3) }
    root.layoutSubtreeIfNeeded()
    do {
        try Harness.png(root, to: outURL)
        print("wrote \(outURL.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write("render failed: \(error)\n".data(using: .utf8)!)
        exit(2)
    }
}

let document = ProjectDocument()
do {
    try document.read(from: projectURL, ofType: "com.kgalligan.reelcut-project")
    document.fileURL = projectURL
} catch {
    FileHandle.standardError.write("read failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

let clips = document.project.snapshot.clips.sorted { $0.start < $1.start }
if selectIndex >= 0, clips.indices.contains(selectIndex) {
    document.selection = [clips[selectIndex].id]
}
document.playhead = Ticks(playheadSeconds * 600_000)
let controller = EditorViewController(document: document)
controller.trackHeight = sizeIndex
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: width, height: height),
    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.contentViewController = controller
window.appearance = NSAppearance(named: appearanceName)
window.setContentSize(NSSize(width: width, height: height))
// The view tree needs a few runloop turns: the splits restore their positions
// from viewDidAppear, and the timeline's thumbnails land through a notification.
controller.viewWillAppear()
controller.viewDidAppear()
controller.refreshFromDocument(isLive: false)
for _ in 0..<12 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    controller.view.layoutSubtreeIfNeeded()
}
// The candidate wash is the sheet's own view state and is deliberately not
// part of `TimelineView.update(...)`, so it is pushed in here — after the
// refresh that would otherwise have run over it — and the last few runloop
// turns below let its `didSet` redisplay land.
if !candidateSpans.isEmpty {
    controller.timeline?.candidateSpans = candidateSpans
}
switch tabName {
case "media": controller.inspector?.select(.media)
case "document": controller.inspector?.select(.document)
default: break
}
for _ in 0..<4 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    controller.view.layoutSubtreeIfNeeded()
}
do {
    try Harness.png(controller.view, to: outURL)
    print("wrote \(outURL.path)")
} catch {
    FileHandle.standardError.write("render failed: \(error)\n".data(using: .utf8)!)
    exit(2)
}
exit(0)
