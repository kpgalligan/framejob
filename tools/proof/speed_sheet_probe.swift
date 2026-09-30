// Issue batch B20 (#109): the Speed sheet names the transition a slowed clip
// gives its neighbour; issue batch B33 (#184): and a transition that already
// plays and grows or shrinks (P4, P6), but not one left as it was (P7).
// Built by `speed_sheet_probe.py` over `harness/build.sh`'s swiftc line and
// run once; it drives the REAL sheet —
// `SpeedSheetController(document:clips:)`, its view loaded, the rate typed
// into its own field and `controlTextDidEndEditing(_:)` called — and prints
// one JSON object on stdout: each row's readout lines and the hint. The
// Python beside it judges them.
//
// The fixture is `source_mirror_probe.py` §5's: 30 fps; track 1 holds A (the
// whole of X, 1 000 000 ticks, at 0) and B (the whole of Y, 2 000 000 ticks,
// at 1 600 000); track 2 holds C (X at 0) and D (the whole of Z, 1 200 000
// ticks, at 1 000 000).
import AppKit
import Foundation

_ = NSApplication.shared

var answer: [String: Any] = [:]
func emit() -> Never {
    let data =
        (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])) ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}
func fail(_ why: String) -> Never {
    answer["error"] = why
    emit()
}

func addMedia(_ document: ProjectDocument, _ path: String, _ duration: Ticks) -> MediaSnapshot {
    document.performGroupedEdit(
        "Media",
        [
            .addMedia(
                descriptor: MediaDescriptor(
                    path: path, kind: .video, duration: duration, width: 1920, height: 1080,
                    fps: .thirty, hasVideo: true, hasAudio: true))
        ])
    guard let media = document.project.snapshot.media.first(where: { $0.path == path }) else {
        fail("add_media \(path) added nothing")
    }
    return media
}

func clipID(_ document: ProjectDocument, track: UInt32, at start: Ticks) -> UInt32 {
    guard let clip = document.project.snapshot.clips.first(where: {
        $0.track == track && $0.start == start
    }) else { fail("no clip on track \(track) at \(start)") }
    return clip.id
}

struct Fixture {
    let document: ProjectDocument
    let a: UInt32, b: UInt32, c: UInt32, d: UInt32
}

func fixture() -> Fixture {
    let document = ProjectDocument()
    guard let one = document.project.snapshot.tracks.first?.id else { fail("no track") }
    document.performGroupedEdit("Track", [.addTrack(index: 1)])
    guard let two = document.project.snapshot.tracks.last?.id, two != one else {
        fail("add_track did not add a second track")
    }
    let x = addMedia(document, "/nowhere/X.mov", 1_000_000)
    let y = addMedia(document, "/nowhere/Y.mov", 2_000_000)
    let z = addMedia(document, "/nowhere/Z.mov", 1_200_000)
    document.performGroupedEdit("Clips", [
        .addClip(track: one, media: x.id, at: 0),
        .addClip(track: one, media: y.id, at: 1_600_000),
        .addClip(track: two, media: x.id, at: 0),
        .addClip(track: two, media: z.id, at: 1_000_000),
    ])
    return Fixture(
        document: document,
        a: clipID(document, track: one, at: 0), b: clipID(document, track: one, at: 1_600_000),
        c: clipID(document, track: two, at: 0), d: clipID(document, track: two, at: 1_000_000))
}

func textFields(in view: NSView) -> [NSTextField] {
    var found: [NSTextField] = []
    if let field = view as? NSTextField { found.append(field) }
    for sub in view.subviews { found += textFields(in: sub) }
    return found
}

/// The sheet on `clips`, the rate typed into its field and the edit ended:
/// the readout's lines, or the reason it could not be read.
func sheet(_ document: ProjectDocument, _ clips: [UInt32], rate: Double) -> [String: Any] {
    let controller = SpeedSheetController(document: document, clips: clips)
    let fields = textFields(in: controller.view)
    guard let rateField = fields.first(where: { $0.delegate === controller }) else {
        return ["error": "no rate field (a text field whose delegate is the controller)"]
    }
    let prefix = "\(clips.count) clip"
    rateField.doubleValue = rate
    controller.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: rateField))
    guard let readout = fields.first(where: { $0.stringValue.hasPrefix(prefix) }) else {
        return ["error": "no readout (a label prefixed \"\(prefix)\")"]
    }
    let hint = fields.first(where: { $0.stringValue.hasPrefix("Faster clips") })?.stringValue
    return [
        "lines": readout.stringValue.components(separatedBy: "\n"),
        "hint": hint.map { $0 as Any } ?? NSNull(),
    ]
}

// Every document lives to the end: the controller holds its document weakly.
let base = fixture()
answer["clips"] = ["A": base.a, "B": base.b, "C": base.c, "D": base.d]
answer["P0"] = sheet(base.document, [base.a], rate: 1)
answer["P1"] = sheet(base.document, [base.a], rate: 0.5)
answer["P2"] = sheet(base.document, [base.c], rate: 0.5)
answer["P3"] = sheet(base.document, [base.a, base.c], rate: 0.5)

let slowed = fixture()
slowed.document.performGroupedEdit("Speed", [.setSpeed(clip: slowed.a, rate: 0.5)])
guard slowed.document.project.snapshot.clip(slowed.b)?.transitionIn != nil else {
    fail("P4's fixture: A at ×0.5 gave B no transition")
}
answer["P4"] = sheet(slowed.document, [slowed.a], rate: 0.4)
answer["P4clips"] = ["A": slowed.a, "B": slowed.b]
answer["P7"] = sheet(slowed.document, [slowed.a], rate: 0.5)

let slower = fixture()
slower.document.performGroupedEdit("Speed", [.setSpeed(clip: slower.a, rate: 0.4)])
guard slower.document.project.snapshot.clip(slower.b)?.transitionIn != nil else {
    fail("P6's fixture: A at ×0.4 gave B no transition")
}
answer["P6"] = sheet(slower.document, [slower.a], rate: 0.5)
answer["P6clips"] = ["A": slower.a, "B": slower.b]

let wiped = fixture()
wiped.document.performGroupedEdit("Transition", [.setTransition(clip: wiped.b, kind: .wipe)])
guard wiped.document.project.snapshot.clip(wiped.b)?.transitionIn?.kind == .wipe else {
    fail("P5's fixture: set_transition wipe on B did not take")
}
answer["P5"] = sheet(wiped.document, [wiped.a], rate: 0.5)
answer["P5clips"] = ["A": wiped.a, "B": wiped.b]
answer["H1"] = answer["P0"]
withExtendedLifetime([base.document, slowed.document, slower.document, wiped.document]) {
    emit()
}
