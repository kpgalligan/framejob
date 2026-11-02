// Road map creator-jobs CU1b1 — the recorder saves the cursor, measured on REAL recordings
// driven in-process through `ScreenRecorder.shared` (spec §11 CU-11…CU-13, CU-18, CU-19):
// recording_probe's granted-tier pattern, so no tool pauses.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`:
//
//   cursor_proof host                 the host's facts, never asserted
//   cursor_proof run <work dir>       K4, K5, K7, K8's recordings into <work dir>/recordings
//
// The answer is one JSON object on stdout; `cursor_proof.py` scores it (ffprobe reads each
// movie's track size, and every cursor file is read back as JSON there).
import AppKit
import ScreenCaptureKit

func spin(_ seconds: Double, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if done() { return true }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return done()
}

func emit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{}".utf8)
    FileHandle.standardOutput.write(data)
    exit(0)
}

func hostFacts() -> [String: Any] {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
    return [
        "preflight": CGPreflightScreenCaptureAccess(),
        "post": CGPreflightPostEventAccess(),
        "locked": (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false,
        "main_bounds": rect(CGDisplayBounds(CGMainDisplayID())),
    ]
}

func rect(_ r: CGRect) -> [Double] {
    [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)]
}

/// One segment as the recorder landed it.
func spell(_ segment: RecordingSegment) -> [String: Any] {
    var out: [String: Any] = [
        "path": segment.descriptor.path, "width": segment.descriptor.width,
        "height": segment.descriptor.height,
    ]
    if let url = segment.cursorURL {
        out["cursor_path"] = url.path
        do {
            _ = try ReelCursor(data: Data(contentsOf: url))
            out["accepted"] = true
        } catch {
            out["accepted"] = false
            out["refusal"] = (error as? ReelCoreError)?.message ?? "\(error)"
        }
    }
    if let problem = segment.cursorProblem { out["cursor_problem"] = problem }
    if let image = segment.cursorImage { out["cursor_image"] = image.rawValue }
    return out
}

/// One recording through `ScreenRecorder.shared`: started, `during(segment)` run once per
/// segment while it records (a pause and a resume between when `pauses`), stopped, landed.
func record(
    _ filter: SCContentFilter, _ choice: RecordingChoice, pauses: Bool,
    during: (Int) -> Void
) -> [String: Any] {
    var out: [String: Any] = [:]
    let recorder = ScreenRecorder.shared
    var finished: Result<RecordingResult, Error>?
    var startError: String?
    var started = false
    recorder.start(filter: filter, choice: choice, mayAsk: false,
                   onFinish: { finished = $0 }) { error in
        startError = error.map { $0.localizedDescription }
        started = true
    }
    out["started"] = spin(ScreenRecorder.armCeiling + 5) { started }
    if let startError { out["start_error"] = startError }
    guard started, startError == nil else { return out }
    _ = spin(3) { recorder.session?.segments.first?.screenHost != nil }
    _ = spin(0.3) { false }
    during(0)
    if pauses {
        do {
            try recorder.pause()
            _ = spin(0.5) { false }
            try recorder.resume()
            out["resumed"] = spin(3) {
                recorder.session?.segments.count == 2
                    && recorder.session?.segments[1].screenHost != nil
            }
            _ = spin(0.3) { false }
            during(1)
        } catch {
            out["pause_error"] = error.localizedDescription
        }
    }
    recorder.stop { _ in }
    out["concluded"] = spin(60) { finished != nil }
    switch finished {
    case .success(let result):
        out["segments"] = result.segments.map(spell)
        out["notes"] = result.cursorSegmentsNote ?? ""
    case .failure(let error):
        out["finish_error"] = error.localizedDescription
    case nil:
        break
    }
    return out
}

func shareable() -> (SCShareableContent?, String) {
    var content: SCShareableContent?
    var failure = ""
    var answered = false
    ScreenRecorder.shareableContent { outcome in
        switch outcome {
        case .success(let listed): content = listed
        case .failure(let error): failure = error.localizedDescription
        }
        answered = true
    }
    _ = spin(20) { answered }
    return (content, failure)
}

/// Warps the pointer to each point, holding each for a quarter second; the points warped.
func warp(_ points: [CGPoint]) -> [[Double]] {
    for point in points {
        CGWarpMouseCursorPosition(point)
        _ = spin(0.25) { false }
    }
    return points.map { [Double($0.x), Double($0.y)] }
}

/// A borderless grey window of `size` points at `origin` (Cocoa coordinates), in front.
func window(_ size: CGSize, at origin: CGPoint) -> NSWindow {
    let made = NSWindow(contentRect: CGRect(origin: origin, size: size), styleMask: [.borderless],
                        backing: .buffered, defer: false)
    made.backgroundColor = NSColor(white: 0.5, alpha: 1)
    made.level = .floating
    made.isReleasedWhenClosed = false
    made.orderFrontRegardless()
    return made
}

func run(_ work: URL) -> [String: Any] {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let folder = work.appendingPathComponent("recordings", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    UserDefaults.standard.setVolatileDomain([
        RecordingFiles.folderDefaultsKey: folder.path,
        FFmpegRewrap.policyDefaultsKey: FFmpegRewrap.Policy.never.rawValue,
        "ApplePersistenceIgnoreState": true,
    ], forName: UserDefaults.argumentDomain)
    var out = hostFacts()
    let (content, failure) = shareable()
    guard let content, !content.displays.isEmpty else {
        out["skipped"] = "no shareable display (" + (failure.isEmpty ? "none listed" : failure) + ")"
        return out
    }
    let exclusion = RecordingExclusion.make(
        includeFrameJobWindows: true, ownBundleID: Bundle.main.bundleIdentifier, panelWindowID: nil)
    guard let display = try? ScreenRecorder.filter(
        for: .display(CGMainDisplayID()), in: content, excluding: exclusion)
    else {
        out["skipped"] = "the main display is not shareable"
        return out
    }
    var choice = RecordingChoice()
    choice.source = .display(CGMainDisplayID())
    choice.folder = folder
    choice.microphone = nil
    choice.systemAudio = false
    let b = CGDisplayBounds(CGMainDisplayID())
    func point(_ k: Int) -> CGPoint {
        CGPoint(x: (b.midX - 300 + Double(k) * 41).rounded(), y: (b.midY - 150 + Double(k) * 23).rounded())
    }

    // K4: Nominal and Best, each paused and resumed, the pointer warped in each segment.
    var k4: [[String: Any]] = []
    for (n, resolution) in [RecordingResolution.nominal, .best].enumerated() {
        var run = choice
        run.resolution = resolution
        var warped: [Int: [[Double]]] = [:]
        var result = record(display, run, pauses: true) { segment in
            let base = n * 10 + segment * 4
            warped[segment] = warp([point(base), point(base + 1), point(base + 2)])
        }
        result["resolution"] = resolution.rawValue
        result["warped"] = [warped[0] ?? [], warped[1] ?? []]
        k4.append(result)
    }
    out["k4"] = k4

    // K7: a directory where the cursor file's `.partial` would go, for this second's stem
    // and the next three; the movie lands, the cursor does not.
    var blockers: [String] = []
    let now = Date()
    for offset in 0..<4 {
        let stem = RecordingFiles.stem(at: now.addingTimeInterval(Double(offset)))
        let partial = folder.appendingPathComponent(stem + ".fjcursor.partial", isDirectory: true)
        try? FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: partial.appendingPathComponent("inside"))
        blockers.append(partial.path)
    }
    var k7 = record(display, choice, pauses: false) { _ in _ = warp([point(30)]) }
    k7["blockers"] = blockers
    out["k7"] = k7
    for path in blockers { try? FileManager.default.removeItem(atPath: path) }

    // K8: the probe's own 1001 × 701 pt window at Nominal.
    let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID() } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let own = window(CGSize(width: 1001, height: 701),
                     at: CGPoint(x: visible.minX + 40, y: visible.maxY - 701 - 40))
    _ = spin(1.0) { false }
    let (fresh, _) = shareable()
    let windowID = CGWindowID(own.windowNumber)
    if let fresh, let filter = try? ScreenRecorder.filter(
        for: .window(windowID), in: fresh, excluding: exclusion)
    {
        var w = choice
        w.source = .window(windowID)
        w.resolution = .nominal
        // Inside the window, in global top-left points.
        let top = (CGDisplayBounds(CGMainDisplayID()).height - own.frame.maxY)
        var k8 = record(filter, w, pauses: false) { _ in
            _ = warp([CGPoint(x: (own.frame.minX + 300).rounded(), y: (top + 200).rounded())])
        }
        k8["window_points"] = [1001, 701]
        k8["filter_scale"] = Double(filter.pointPixelScale)
        out["k8"] = k8
    } else {
        out["k8"] = ["skipped": "the probe's window \(windowID) is not shareable"]
    }

    // K5: clicks posted onto the probe's window, only when this process may post.
    if CGPreflightPostEventAccess() {
        let top = (CGDisplayBounds(CGMainDisplayID()).height - own.frame.maxY)
        let at = CGPoint(x: (own.frame.minX + 500).rounded(), y: (top + 350).rounded())
        var k5 = record(display, choice, pauses: false) { _ in
            CGWarpMouseCursorPosition(at)
            _ = spin(0.2) { false }
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: at,
                        mouseButton: .left)?.post(tap: .cghidEventTap)
                _ = spin(0.2) { false }
            }
            _ = spin(0.3) { false }
        }
        k5["posted"] = [Double(at.x), Double(at.y)]
        out["k5"] = k5
    } else {
        out["k5"] = ["skipped": "CGPreflightPostEventAccess() is false: this process cannot post input"]
    }
    own.close()
    return out
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: cursor_proof host | run <work dir>\n".utf8))
    exit(2)
}
switch arguments[1] {
case "host":
    emit(hostFacts())
case "run" where arguments.count == 3:
    emit(run(URL(fileURLWithPath: arguments[2], isDirectory: true)))
default:
    FileHandle.standardError.write(Data("usage: cursor_proof host | run <work dir>\n".utf8))
    exit(2)
}
