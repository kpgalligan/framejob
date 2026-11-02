// Road map "creator-jobs" CU5 (spec §11 CU-54, CU-55): M3, the probe row of `cu5_proof.py`,
// compiled as `main.swift` over `app/Sources` through `swift_build.build()` with
// `FRAMEJOB_DEV_TOOLS`, and run as `cu5-probe <request.json>`. The request names two cursor
// files the proof wrote (`good`, `movie_size` 640 × 360, and `wrong`, 320 × 180) and a path that
// does not exist (`absent`). It prints one JSON object, `{"rows": [{"id", "pass", "detail"}]}`.
//
// - M3 (a) `MediaPane.cursorLine`'s four strings: no media, and an audio media, "Select a video
//   in the list"; a video with none, "No cursor file"; a video whose file exists, its name; one
//   whose file is missing, "<name> — missing".
// - M3 (b) the app's own `MediaPane` over a `ProjectDocument` (no window), rebuilt by the
//   inspector's rule: no `media.cursor` section with only an audio media or only a video with
//   no picture; the section, titled "Cursor", with a video with a picture and no cursor file,
//   and still there once a cursor set by `set_media_cursor` is removed by it again.
// - M3 (c) Locate's attach (`MediaImporter.cursorAttachment` against `MediaDescriptor(media)`):
//   `wrong` refused in CU-34's sentence naming both sizes; `good` attached with its own path
//   and `in_picture`.

import AppKit
import Foundation

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": detail])
}

func finish() -> Never {
    let data =
        (try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.sortedKeys]))
        ?? Data()
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

guard CommandLine.arguments.count > 1,
    let requestData = FileManager.default.contents(atPath: CommandLine.arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let good = request["good"] as? String, let wrong = request["wrong"] as? String,
    let absent = request["absent"] as? String
else {
    row("M3", false, "no request")
    finish()
}

let moviePath = "/proof/cu5/A.mov"
func video(_ cursor: MediaCursor?, hasVideo: Bool = true) -> MediaSnapshot {
    MediaSnapshot(
        id: 1, path: moviePath, kind: .video, duration: 600_000, width: 640, height: 360,
        hasVideo: hasVideo, cursor: cursor)
}

var problems: [String] = []
var notes: [String] = []

// (a) the readout's four strings.
let goodName = URL(fileURLWithPath: good).lastPathComponent
let absentName = URL(fileURLWithPath: absent).lastPathComponent
let lines: [(String, MediaSnapshot?, String)] = [
    ("none selected", nil, "Select a video in the list"),
    ("an audio media", MediaSnapshot(id: 2, path: "/proof/cu5/a.wav", kind: .audio,
                                      hasVideo: false, hasAudio: true),
     "Select a video in the list"),
    ("no cursor", video(nil), "No cursor file"),
    ("a file", video(MediaCursor(path: good, inPicture: false)), goodName),
    ("a missing file", video(MediaCursor(path: absent, inPicture: false)),
     "\(absentName) — missing"),
]
for (label, media, want) in lines {
    let got = MediaPane.cursorLine(media)
    if got != want { problems.append("\(label): \"\(got)\", not \"\(want)\"") }
}
notes.append("(a) \(lines.count) readouts")

// (b) the section in the app's own Media pane.
final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = AppDelegate()
delegate.applicationWillFinishLaunching(
    Notification(name: NSApplication.willFinishLaunchingNotification, object: app))
var kept: [AnyObject] = []

func mediaPane(_ descriptors: [MediaDescriptor]) -> (ProjectDocument, MediaPane) {
    let document = ProjectDocument()
    for descriptor in descriptors {
        document.performGroupedEdit("Media", [.addMedia(descriptor: descriptor)])
    }
    document.selectedMedia = document.project.snapshot.media.first?.id
    let inspector = InspectorViewController()
    inspector.document = document
    inspector.onEdit = { [weak document] name, ops in document?.applyEdit(name, ops) }
    inspector.binding.invalidate()
    let pane = MediaPane(inspector: inspector)
    kept += [document, inspector, pane]
    pane.binding.invalidate()
    pane.rebuild()
    pane.refresh()
    return (document, pane)
}

func sectionIDs(_ pane: MediaPane) -> [String] {
    pane.binding.invalidate()
    pane.rebuild()
    pane.refresh()
    return pane.sections.map(\.id)
}

let audio = MediaDescriptor(
    path: "/proof/cu5/a.wav", kind: .audio, duration: 600_000, hasVideo: false, hasAudio: true)
let blind = MediaDescriptor(
    path: "/proof/cu5/blind.mov", kind: .video, duration: 600_000, width: 640, height: 360,
    hasVideo: false, hasAudio: true)
let picture = MediaDescriptor(
    path: moviePath, kind: .video, duration: 600_000, width: 640, height: 360, hasVideo: true)
let (_, audioPane) = mediaPane([audio])
let (_, blindPane) = mediaPane([blind])
let (pictureDocument, picturePane) = mediaPane([picture])
let audioIDs = sectionIDs(audioPane)
let blindIDs = sectionIDs(blindPane)
let pictureIDs = sectionIDs(picturePane)
if audioIDs.contains("media.cursor") { problems.append("an audio media shows it: \(audioIDs)") }
if blindIDs.contains("media.cursor") {
    problems.append("a video with no picture shows it: \(blindIDs)")
}
if !pictureIDs.contains("media.cursor") {
    problems.append("a video with a picture lacks it: \(pictureIDs)")
}
let title = picturePane.sections.first { $0.id == "media.cursor" }?.title
if title != "Cursor" { problems.append("title \(title ?? "none")") }
if let id = pictureDocument.project.snapshot.media.first?.id {
    pictureDocument.performGroupedEdit(
        "Locate Cursor File",
        [.setMediaCursor(media: id, cursor: MediaCursor(path: good, inPicture: false))])
    let set = pictureDocument.project.snapshot.media(id)?.cursor?.path
    let withIDs = sectionIDs(picturePane)
    pictureDocument.performGroupedEdit(
        "Remove Cursor File", [.setMediaCursor(media: id, cursor: nil)])
    let cleared = pictureDocument.project.snapshot.media(id)?.cursor
    let afterIDs = sectionIDs(picturePane)
    if set != good { problems.append("set_media_cursor stored \(set ?? "nothing")") }
    if cleared != nil { problems.append("set_media_cursor null left \(String(describing: cleared))") }
    if !withIDs.contains("media.cursor") || !afterIDs.contains("media.cursor") {
        problems.append("with a cursor \(withIDs), after Remove \(afterIDs)")
    }
}
notes.append("(b) audio \(audioIDs), no picture \(blindIDs), picture \(pictureIDs)")

// (c) Locate's attach check.
let target = MediaDescriptor(video(nil))
switch MediaImporter.cursorAttachment(at: URL(fileURLWithPath: wrong), to: target) {
case .success:
    problems.append("the 320 × 180 file was attached")
case .failure(let problem):
    let want = "The cursor file \(URL(fileURLWithPath: wrong).lastPathComponent) was not "
        + "attached: its movie_size is 320 × 180 and the movie is 640 × 360."
    if problem.message != want { problems.append("wrong size said \"\(problem.message)\"") }
    notes.append("(c) \(problem.message)")
}
switch MediaImporter.cursorAttachment(at: URL(fileURLWithPath: good), to: target) {
case .success(let attachment):
    if attachment.cursor.path != good || attachment.cursor.inPicture {
        problems.append("the good file attached as \(attachment.cursor.dictionary)")
    }
case .failure(let problem):
    problems.append("the good file was refused: \(problem.message)")
}

row("M3", problems.isEmpty, (problems + notes).joined(separator: "; "))
finish()
