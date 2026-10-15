// Built by tools/proof/hdr_proof.py as `main.swift` over every other file in
// `app/Sources` (`swift_build.py`). See that script's header, rows H1 and H6
// (grading-3 T3-1, spec §11 GR-15).
//
// The chroma key's canvas eyedropper (Video ▸ Chroma Key ▸ Pick from Canvas),
// driven through the app's own code with no window: what
// `EditorViewController.chromaKeyPicked(at:)` does once the click is mapped to
// a canvas point. The package is opened as a `ProjectDocument`, the session's
// `suppression` applied to a copy of the project (pure, never published), the
// frame composed by `Exporter.renderFrame` at the tick, and the pixel read by
// `CanvasEyedropperSession.color(at:in:canvas:)`; the key written is
// `session.chroma(picked:)`'s. Existing API only, so the probe builds on the
// tree before T3-1 (the control) and after it.
//
// Two optional keys (grading-3 T3-1, revision 2): `"png"`, a path the composed
// frame is written to through `FrameWriter.write(_:as: .png, to:)` (what
// `render_frame` writes with, minus spec §11 PR-11's BT.709 label, which
// `render_frame` applies through `FrameWriter.writeFrame` since issue batch
// B102; it stays `write` so the probe still builds on older trees), and
// `"plain"`, a media file read INSTEAD of a
// package: its own frame from an `AVAssetImageGenerator` over the plain asset
// (no composition) — Apple's reading of the file's own labels (H1w's oracle) —
// picked with the same `color(at:in:canvas:)` on a canvas the frame's size.
//
// argv[1] is the request (JSON), argv[2] the answer (JSON). The request is
// `{"picks": [{"tag", "package" | "plain", "tick", "clips": [id…], "points":
// [[x, y]…], "png"?}]}` (points in canvas pixels); each answer row is `{"tag",
// "picked": [[r, g, b] or null …], "keys": [[r, g, b] or null …]}` or `{"tag",
// "error"}`.
import AVFoundation
import AppKit

let arguments = CommandLine.arguments
let requestURL = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "")
let outURL = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "")
let request =
    (try? JSONSerialization.jsonObject(with: Data(contentsOf: requestURL)) as? [String: Any])
    ?? [:]

func openDocument(_ path: String) -> ProjectDocument? {
    let document = ProjectDocument()
    do {
        try document.read(
            from: URL(fileURLWithPath: path), ofType: ProjectDocument.projectTypeIdentifier)
        document.fileURL = URL(fileURLWithPath: path)
    } catch {
        return nil
    }
    return document
}

func plainFrame(_ path: String, tick: Ticks) -> CGImage? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = false
    return try? generator.copyCGImage(at: CompositionBuilder.time(tick), actualTime: nil)
}

func read(_ frame: CGImage, _ spec: [String: Any], session: CanvasEyedropperSession,
          canvas: CanvasSnapshot) -> [String: Any] {
    let tag = spec["tag"] as? String ?? "?"
    var colours: [Any] = []
    var keys: [Any] = []
    for point in spec["points"] as? [[Double]] ?? [] where point.count == 2 {
        let at = CGPoint(x: point[0], y: point[1])
        if let colour = CanvasEyedropperSession.color(at: at, in: frame, canvas: canvas) {
            colours.append(colour)
            keys.append(session.chroma(picked: colour).key)
        } else {
            colours.append(NSNull())
            keys.append(NSNull())
        }
    }
    var row: [String: Any] = ["tag": tag, "picked": colours, "keys": keys,
                              "width": frame.width, "height": frame.height]
    if let png = spec["png"] as? String {
        do {
            _ = try FrameWriter.write(frame, as: .png, to: URL(fileURLWithPath: png))
            row["png"] = png
        } catch {
            row["error"] = "the PNG was not written: \(error)"
        }
    }
    return row
}

func picked(_ spec: [String: Any]) -> [String: Any] {
    let tag = spec["tag"] as? String ?? "?"
    let tick = Ticks(spec["tick"] as? Int ?? 0)
    let session = CanvasEyedropperSession(
        clips: (spec["clips"] as? [NSNumber] ?? []).map(\.uint32Value), base: nil)
    if let plain = spec["plain"] as? String {
        guard let frame = plainFrame(plain, tick: tick) else {
            return ["tag": tag, "error": "the plain asset's generator answered nil"]
        }
        return read(frame, spec, session: session,
                    canvas: CanvasSnapshot(width: frame.width, height: frame.height))
    }
    guard let document = openDocument(spec["package"] as? String ?? "") else {
        return ["tag": tag, "error": "the package would not open"]
    }
    let edited = document.editedProject
    let project = (try? edited.applying([session.suppression])).project ?? edited
    guard let frame = Exporter.renderFrame(
        project: project, urls: document.mediaURLs(), at: tick, maxWidth: nil)
    else { return ["tag": tag, "error": "Exporter.renderFrame answered nil"] }
    return read(frame, spec, session: session, canvas: edited.snapshot.canvas)
}

NSApplication.shared.setActivationPolicy(.prohibited)
let rows = (request["picks"] as? [[String: Any]] ?? []).map(picked)
let answer: [String: Any] = ["rows": rows]
if let data = try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted]) {
    try? data.write(to: outURL)
}
exit(0)
