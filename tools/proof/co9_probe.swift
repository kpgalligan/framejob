// Road map "creator-jobs" CO9 (spec §11 CO-94, CO-95): the probe of `co9_proof.py`, compiled as
// `main.swift` over `app/Sources` through `swift_build.build()` with `FRAMEJOB_DEV_TOOLS`, so
// every row drives the app's own `DuckSpeech`, `HideSilentSources`, `ClipPane`,
// `VideoPane+HideSilent` and `ProjectDocument`.
//
//   co9-probe <request.json>
//
// The request names `camera` and `mic` (the proof's white movie with no sound and its sine
// file). Every fixture is one untitled document whose media are added by descriptor. One JSON
// object on stdout, `{"rows": [{"id", "pass", "detail"}]}`.
//
// - P1 `DuckSpeech.ops(forMedia:)`: the mic with an empty cache folder throws "…'s speech has
//   not been detected yet…" (and `problem(forMedia:)` says the same); with a stamped speech
//   cache one `set_media_speech` whose spans are `DuckSpeech.spans` of it (`problem` nil); once
//   the media has `speech`, `[]`; an unknown id `[]`; the camera (no sound) throws "… has no
//   sound, so a clip cannot hide while it is silent."
// - P2 `HideSilentSources.candidates` for the selected camera (0–4 s, no sound): a music bed
//   (audio only, 0–4 s, the higher id), the mic (audio only, 1–3 s), a second camera with sound
//   (0–4 s), not a later mic (10–12 s) nor the camera itself: [bed, mic, camera 2] — the
//   picture-less first, then the overlap, then the id.
// - P3 (a windowless `ClipPane`): `video.hide_silent` directly after `video.layout` with the
//   camera selected; its checkbox, with the mic's cache stamped, sends ONE edit "Hide While
//   Silent" whose ops are `set_media_speech` then `set_video`; after it the mic has its spans
//   and the camera `{media: mic}` at the defaults; one undo restores the project byte for byte.

import AppKit

var rows: [[String: Any]] = []

func row(_ id: String, _ pass: Bool, _ detail: String) {
    rows.append(["id": id, "pass": pass, "detail": String(detail.prefix(1500))])
}

func printJSON(_ object: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

guard CommandLine.arguments.count == 2,
    let requestData = FileManager.default.contents(atPath: CommandLine.arguments[1]),
    let request = (try? JSONSerialization.jsonObject(with: requestData)) as? [String: Any],
    let cameraPath = request["camera"] as? String, let micPath = request["mic"] as? String
else {
    for id in ["P1", "P2", "P3"] { row(id, false, "the request could not be read") }
    printJSON(["rows": rows])
    exit(0)
}

final class ProbeDocumentController: NSDocumentController {
    override var defaultType: String? { ProjectDocument.projectTypeIdentifier }
}
_ = ProbeDocumentController()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let second: Ticks = 600_000
var documents: [ProjectDocument] = []
var kept: [AnyObject] = []

func spin(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func finish() -> Never {
    for document in documents { document.removeTemporaryCacheDirectory() }
    printJSON(["rows": rows])
    exit(0)
}

/// A media added by descriptor; its id.
func add(_ document: ProjectDocument, _ path: String, video: Bool, audio: Bool) -> UInt32? {
    let before = Set(document.project.snapshot.media.map(\.id))
    document.performGroupedEdit("Media", [.addMedia(descriptor: MediaDescriptor(
        path: path, kind: video ? .video : .audio, duration: 20 * second,
        width: video ? 1920 : 0, height: video ? 1080 : 0, fps: .thirty,
        hasVideo: video, hasAudio: audio))])
    return document.project.snapshot.media.map(\.id).first { !before.contains($0) }
}

/// A clip of `media` on track index `index` (made when missing) at `at`, trimmed to `end`.
func place(_ document: ProjectDocument, _ media: UInt32, _ index: Int, at: Ticks, end: Ticks)
    -> UInt32?
{
    while document.project.snapshot.tracks.count <= index {
        document.performGroupedEdit(
            "Track", [.addTrack(index: document.project.snapshot.tracks.count)])
    }
    let track = document.project.snapshot.tracks[index].id
    let before = Set(document.project.snapshot.clips.map(\.id))
    document.performGroupedEdit("Clip", [.addClip(track: track, media: media, at: at)])
    guard let clip = document.project.snapshot.clips.map(\.id).first(where: {
        !before.contains($0)
    }) else { return nil }
    document.performGroupedEdit("Trim", [.trimEnd(clip: clip, to: end)])
    return clip
}

/// A stamped speech cache for `media`: chunks 20–59 speech, the rest silence; its spans.
func stampSpeech(_ document: ProjectDocument, _ media: UInt32) -> [[Ticks]]? {
    guard let directory = document.cacheDirectory,
          let row = document.project.snapshot.media(media)
    else { return nil }
    var p = [Float](repeating: 0, count: MediaSpeech.chunkCount(duration: row.duration))
    for i in 20..<60 where i < p.count { p[i] = 0.9 }
    let file = MediaImporter.speechURL(for: media, in: directory)
    try? FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let wrote = (try? p.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: file)) != nil
        && MediaImporter.writeStamp(
            MediaImporter.SpeechStamp(
                MediaImporter.CacheStamp(
                    size: 0, modified: 0, duration: row.duration, width: 0, height: 0,
                    hasVideo: false, hasAudio: true, thumbnailHeight: 0, maxThumbnails: 0,
                    peakBucketsPerSecond: 0)),
            to: MediaImporter.speechMarkerURL(for: media, in: directory))
    return wrote ? DuckSpeech.spans(p, duration: row.duration) : nil
}

func message(_ body: () throws -> [ReelOp]) -> String {
    do {
        _ = try body()
        return "no throw"
    } catch {
        return error.localizedDescription
    }
}

func walk(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(walk) }

// ---- P1 -------------------------------------------------------------------------------------

do {
    let document = ProjectDocument()
    documents.append(document)
    var problems: [String] = []
    if let mic = add(document, micPath, video: false, audio: true),
       let camera = add(document, cameraPath, video: true, audio: false),
       let directory = document.cacheDirectory
    {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func ops(_ media: UInt32) throws -> [ReelOp] {
            try DuckSpeech.ops(
                forMedia: media, in: document.project.snapshot, cacheDirectory: directory)
        }
        func problem(_ media: UInt32) -> String? {
            DuckSpeech.problem(
                forMedia: media, in: document.project.snapshot, cacheDirectory: directory)
        }
        let empty = message { try ops(mic) }
        if !empty.contains("speech has not been detected yet, so a clip cannot hide while it is "
            + "silent. Try again in a moment.")
        {
            problems.append("an empty cache folder: \(empty)")
        }
        if problem(mic) != empty { problems.append("problem with no cache: \(String(describing: problem(mic)))") }
        if let spans = stampSpeech(document, mic) {
            let found = (try? ops(mic)) ?? []
            if found.map(\.name) != ["set_media_speech"] {
                problems.append("a stamped cache answered \(found.map(\.name))")
            }
            if problem(mic) != nil { problems.append("problem with a cache: \(problem(mic)!)") }
            document.performGroupedEdit("Speech", found)
            if document.project.snapshot.media(mic)?.speech != spans || spans.isEmpty {
                problems.append("the saved spans are not the cache's \(spans)")
            }
            let again = (try? ops(mic)).map { $0.map(\.name) } ?? ["threw"]
            if !again.isEmpty { problems.append("a media with speech answered \(again)") }
        } else {
            problems.append("the cache could not be written")
        }
        let unknown = (try? ops(9999)).map { $0.map(\.name) } ?? ["threw"]
        if !unknown.isEmpty { problems.append("an unknown media answered \(unknown)") }
        let silent = message { try ops(camera) }
        if !silent.hasSuffix(" has no sound, so a clip cannot hide while it is silent.") {
            problems.append("the camera: \(silent)")
        }
        row("P1", problems.isEmpty,
            problems.isEmpty
                ? "empty cache: \(empty); a stamped cache one set_media_speech, then []; unknown "
                    + "[]; the camera: \(silent)"
                : problems.joined(separator: "; "))
    } else {
        row("P1", false, "the fixture could not be made")
    }
}

// ---- P2 -------------------------------------------------------------------------------------

do {
    let document = ProjectDocument()
    documents.append(document)
    if let camera = add(document, cameraPath, video: true, audio: false),
       let mic = add(document, micPath, video: false, audio: true),
       let camera2 = add(document, cameraPath + ".2.mov", video: true, audio: true),
       let bed = add(document, micPath + ".bed.m4a", video: false, audio: true),
       let later = add(document, micPath + ".later.m4a", video: false, audio: true),
       let cameraClip = place(document, camera, 0, at: 0, end: 4 * second),
       place(document, mic, 1, at: second, end: 3 * second) != nil,
       place(document, camera2, 2, at: 0, end: 4 * second) != nil,
       place(document, bed, 3, at: 0, end: 4 * second) != nil,
       place(document, later, 4, at: 10 * second, end: 12 * second) != nil,
       let selected = document.project.snapshot.clip(cameraClip)
    {
        let found = HideSilentSources.candidates(for: [selected], in: document.project.snapshot)
            .map(\.id)
        let want = [bed, mic, camera2]
        row("P2", found == want, "candidates \(found) (want \(want): bed \(bed), mic \(mic), "
            + "camera 2 \(camera2); not later \(later) nor the camera \(camera))")
    } else {
        row("P2", false, "the fixture could not be made")
    }
}

// ---- P3 -------------------------------------------------------------------------------------

do {
    let document = ProjectDocument()
    documents.append(document)
    if let camera = add(document, cameraPath, video: true, audio: false),
       let mic = add(document, micPath, video: false, audio: true),
       let cameraClip = place(document, camera, 1, at: 0, end: 4 * second),
       place(document, mic, 0, at: 0, end: 4 * second) != nil,
       let spans = stampSpeech(document, mic)
    {
        var problems: [String] = []
        var heard: [(String, [String])] = []
        let inspector = InspectorViewController()
        inspector.document = document
        inspector.onEdit = { [weak document] name, ops in
            heard.append((name, ops.map(\.name)))
            document?.applyEdit(name, ops)
        }
        document.selection = [cameraClip]
        inspector.binding.invalidate()
        let pane = ClipPane(inspector: inspector)
        kept += [inspector, pane]
        pane.binding.invalidate()
        pane.choose(.picture)
        pane.rebuild()
        pane.refresh()
        let order = pane.sections.map(\.id)
        if let layout = order.firstIndex(of: "video.layout"),
           let hide = order.firstIndex(of: "video.hide_silent")
        {
            if hide != layout + 1 { problems.append("sections \(order)") }
        } else {
            problems.append("sections \(order) lack video.layout or video.hide_silent")
        }
        let section = pane.sections.first { $0.id == "video.hide_silent" }
        let check = section.flatMap { walk($0).compactMap { $0 as? OptionCheckboxControl }.first }
        let before = document.project.json
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        if let check, let event {
            check.mouseDown(with: event)
            spin(0.2)
        } else {
            problems.append("no checkbox in the section")
        }
        let snapshot = document.project.snapshot
        let gate = snapshot.clip(cameraClip)?.video?.hideSilent
        if heard.count != 1 || heard.first?.0 != "Hide While Silent"
            || heard.first?.1 != ["set_media_speech", "set_video"]
        {
            problems.append("the edits sent \(heard)")
        }
        if snapshot.media(mic)?.speech != spans { problems.append("the mic's spans were not saved") }
        if gate != HideSilentProps(media: mic) {
            problems.append("the camera's gate \(String(describing: gate))")
        }
        let named = document.undoManager?.undoActionName ?? ""
        document.undoManager?.undo()
        spin(0.1)
        if named != "Hide While Silent" || document.project.json != before {
            problems.append("one undo (\(named.debugDescription)) did not restore the project")
        }
        row("P3", problems.isEmpty,
            problems.isEmpty
                ? "sections \(order); the checkbox sent \(heard), saved the spans and the gate; "
                    + "one undo \"Hide While Silent\" restored the project"
                : problems.joined(separator: "; "))
    } else {
        row("P3", false, "the fixture could not be made")
    }
}

finish()
