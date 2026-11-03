// Road map creator-jobs CU1b1 — the recorder saves the cursor, measured on REAL recordings
// driven in-process through `ScreenRecorder.shared` (spec §11 CU-11…CU-13, CU-18, CU-19):
// recording_probe's granted-tier pattern, so no tool pauses.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`:
//
//   cursor_proof host                 the host's facts, never asserted
//   cursor_proof run <work dir>       K4, K5, K7, K8's recordings into <work dir>/recordings
//   cursor_proof cu3c <work dir>      CU3c's B1 and B4 recordings (road map creator-jobs CU3c,
//                                     spec §11 CU-31) into <work dir>/cu3c, and the arrow's
//                                     black centroid for B4's located tip
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

// MARK: - CU3c: B1 a window recorded Separate and In the picture, B4 a moving red square

/// Frame Job's arrow at its 1× size (14 × 21 px): the centroid of its BLACK coverage —
/// `(alpha − white) / 255` of each premultiplied texel, kept at 0.3 or more as `tip_from` keeps
/// α — less its hot spot, in pixels; what `cursor_proof.py` subtracts from a located centroid.
func arrowCentroid() -> [String: Any] {
    let (w, h) = CursorArrow.pixelSize(pxPerPoint: 1, scale: 1)
    guard let raster = try? GraphicLibrary().rasterize(
        CursorArrow.svg(width: w, height: h), width: w, height: h)
    else { return ["error": "the arrow did not rasterize"] }
    var total = 0.0, sx = 0.0, sy = 0.0
    for y in 0..<raster.height {
        for x in 0..<raster.width {
            let i = y * raster.stride + x * 4
            let rgb = (Double(raster.bgra[i]) + Double(raster.bgra[i + 1])
                + Double(raster.bgra[i + 2])) / 3
            let black = max(0, (Double(raster.bgra[i + 3]) - rgb) / 255)
            guard black >= 0.3 else { continue }
            total += black
            sx += black * (Double(x) + 0.5)
            sy += black * (Double(y) + 0.5)
        }
    }
    guard total > 0 else { return ["error": "the arrow has no black texel"] }
    return ["size": [w, h],
            "offset": [sx / total - Double(CursorArrow.hotSpot.x),
                       sy / total - Double(CursorArrow.hotSpot.y)]]
}

func cu3c(_ work: URL) -> [String: Any] {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let folder = work.appendingPathComponent("cu3c", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    UserDefaults.standard.setVolatileDomain([
        RecordingFiles.folderDefaultsKey: folder.path,
        FFmpegRewrap.policyDefaultsKey: FFmpegRewrap.Policy.never.rawValue,
        "ApplePersistenceIgnoreState": true,
    ], forName: UserDefaults.argumentDomain)
    var out = hostFacts()
    out["arrow"] = arrowCentroid()
    let exclusion = RecordingExclusion.make(
        includeFrameJobWindows: true, ownBundleID: Bundle.main.bundleIdentifier, panelWindowID: nil)
    var choice = RecordingChoice()
    choice.folder = folder
    choice.microphone = nil
    choice.systemAudio = false
    choice.resolution = .nominal
    let displayHeight = CGDisplayBounds(CGMainDisplayID()).height

    // B1: the probe's grey window, the pointer warped inside it, recorded each way.
    let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID() } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let own = window(CGSize(width: 1001, height: 701),
                     at: CGPoint(x: visible.minX + 40, y: visible.maxY - 701 - 40))
    _ = spin(1.0) { false }
    let (fresh, failure) = shareable()
    let windowID = CGWindowID(own.windowNumber)
    let top = displayHeight - own.frame.maxY
    let at = CGPoint(x: (own.frame.minX + 300).rounded(), y: (top + 200).rounded())
    var b1: [String: Any] = ["origin": [Double(own.frame.minX), Double(top)],
                             "points": [1001, 701], "warped": [Double(at.x), Double(at.y)]]
    if let fresh, let filter = try? ScreenRecorder.filter(
        for: .window(windowID), in: fresh, excluding: exclusion)
    {
        for cursor in RecordingCursor.allCases {
            var w = choice
            w.source = .window(windowID)
            w.cursor = cursor
            b1[cursor.rawValue] = record(filter, w, pauses: false) { _ in
                CGWarpMouseCursorPosition(at)
                _ = spin(1.0) { false }
            }
        }
    } else {
        b1["skipped"] = "the probe's window \(windowID) is not shareable (\(failure))"
    }
    own.close()
    out["b1"] = b1

    // B4: a red 40 pt square whose top-left corner the pointer holds at 8 points, 0.5 s each.
    guard let content = fresh, let display = try? ScreenRecorder.filter(
        for: .display(CGMainDisplayID()), in: content, excluding: exclusion)
    else {
        out["b4"] = ["skipped": "the main display is not shareable"]
        return out
    }
    let b = CGDisplayBounds(CGMainDisplayID())
    let holds = (0..<8).map { k -> CGPoint in
        let column = Double(k % 4) * 230
        let row = Double(k / 4) * 260 + Double(k % 2) * 37
        let x: Double = b.midX - 400 + column
        let y: Double = b.midY - 200 + row
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
    let square = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    square.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    square.level = .floating
    square.isReleasedWhenClosed = false
    func place(_ p: CGPoint) {
        square.setFrameOrigin(CGPoint(x: p.x, y: displayHeight - p.y - 40))
        CGWarpMouseCursorPosition(p)
    }
    place(holds[0])
    square.orderFrontRegardless()
    _ = spin(0.5) { false }
    var s = choice
    s.source = .display(CGMainDisplayID())
    s.cursor = .separate
    s.rate = 30
    var placed: [Double] = []
    var started: Double?
    var b4 = record(display, s, pauses: false) { _ in
        started = ScreenRecorder.shared.session?.segments.first?.screenHost
        for p in holds {
            place(p)
            placed.append(CursorCapture.hostNow())
            _ = spin(0.5) { false }
        }
    }
    square.close()
    b4["holds"] = holds.map { [Double($0.x), Double($0.y)] }
    b4["placed_host"] = placed
    if let started { b4["screen_host"] = started }
    out["b4"] = b4
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
case "cu3c" where arguments.count == 3:
    emit(cu3c(URL(fileURLWithPath: arguments[2], isDirectory: true)))
default:
    FileHandle.standardError.write(Data("usage: cursor_proof host | run <work dir>\n".utf8))
    exit(2)
}
