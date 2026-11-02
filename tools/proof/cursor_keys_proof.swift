// Road map creator-jobs CU6 — record shortcuts on a REAL recording, driven in-process through
// `ScreenRecorder.shared` with `keys` `shortcuts` (spec §11 CU-60, CU-63, rows Y3 and Y4):
// cursor_proof's granted pattern, so no tool pauses.
//
// Compiled AS `main.swift` over every file in `app/Sources` but the app's own `main.swift`,
// against `libframejob_core.a`, through `swift_build.py`:
//
//   cursor_keys_proof host              the host's facts, never asserted
//   cursor_keys_proof run <work dir>    the recording into <work dir>/recordings
//
// The run puts a grey 600 × 400 pt window on the main display, makes it key in this process,
// and POSTS key-downs into it: ⌘⇧F19 and five letters (Y3), five letters under this process's
// `EnableSecureEventInput()` (Y4), then two more. It never posts while another application is
// active. The answer is one JSON object on stdout; `cursor_keys_proof.py` scores it, reading the
// cursor file back as JSON, each phase's span in the file's µs.
import AppKit
import Carbon.HIToolbox
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
        "listen": CGPreflightListenEventAccess(),
        "post": CGPreflightPostEventAccess(),
        "locked": (session?["CGSSessionScreenIsLocked"] as? Bool) ?? false,
    ]
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

/// One key-down and its key-up, posted at the HID level with `flags`.
func post(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        else { continue }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        _ = spin(0.08) { false }
    }
}

let letters: [CGKeyCode] = [
    CGKeyCode(kVK_ANSI_J), CGKeyCode(kVK_ANSI_K), CGKeyCode(kVK_ANSI_L), CGKeyCode(kVK_ANSI_U),
    CGKeyCode(kVK_ANSI_I),
]

func run(_ work: URL) -> [String: Any] {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
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
    guard let filter = try? ScreenRecorder.filter(
        for: .display(CGMainDisplayID()), in: content, excluding: exclusion)
    else {
        out["skipped"] = "the main display is not shareable"
        return out
    }
    // The window the keys go to: this process's own, key and in front.
    let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    let window = NSWindow(
        contentRect: CGRect(x: visible.minX + 60, y: visible.maxY - 460, width: 600, height: 400),
        styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "cursor_keys_proof"
    window.backgroundColor = NSColor(white: 0.5, alpha: 1)
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    guard spin(3, { app.isActive && window.isKeyWindow }) else {
        out["skipped"] = "this process could not become the active application, so a posted "
            + "key would reach another one"
        window.close()
        return out
    }

    var choice = RecordingChoice()
    choice.source = .display(CGMainDisplayID())
    choice.folder = folder
    choice.microphone = nil
    choice.systemAudio = false
    choice.keys = .shortcuts
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
    guard started, startError == nil else {
        window.close()
        return out
    }
    out["records_keys"] = recorder.recordsKeys
    _ = spin(3) { recorder.session?.segments.first?.screenHost != nil }
    let anchor = recorder.session?.segments.first?.screenHost ?? CursorCapture.hostNow()
    func micros(_ host: Double) -> Int { Int(((host - anchor) * 1_000_000).rounded()) }
    _ = spin(0.3) { false }

    var spans: [String: [Int]] = [:]
    var frontWhilePosting = true
    // Y3: ⌘⇧F19, then five letters.
    var from = CursorCapture.hostNow()
    frontWhilePosting = frontWhilePosting && app.isActive
    post(CGKeyCode(kVK_F19), [.maskCommand, .maskShift])
    for letter in letters { post(letter) }
    _ = spin(0.3) { false }
    spans["y3"] = [micros(from), micros(CursorCapture.hostNow())]
    // Y4: five letters under secure input, then two after it.
    EnableSecureEventInput()
    _ = spin(0.2) { false }
    out["secure_on"] = IsSecureEventInputEnabled()
    from = CursorCapture.hostNow()
    frontWhilePosting = frontWhilePosting && app.isActive
    for letter in letters { post(letter) }
    _ = spin(0.3) { false }
    spans["secure"] = [micros(from), micros(CursorCapture.hostNow())]
    DisableSecureEventInput()
    _ = spin(0.3) { false }
    out["secure_off"] = !IsSecureEventInputEnabled()
    from = CursorCapture.hostNow()
    frontWhilePosting = frontWhilePosting && app.isActive
    for letter in letters.prefix(2) { post(letter) }
    _ = spin(0.3) { false }
    spans["after"] = [micros(from), micros(CursorCapture.hostNow())]
    out["spans"] = spans
    out["front_while_posting"] = frontWhilePosting

    recorder.stop { _ in }
    out["concluded"] = spin(60) { finished != nil }
    switch finished {
    case .success(let result):
        out["segments"] = result.segments.map { segment -> [String: Any] in
            var spelled: [String: Any] = ["path": segment.descriptor.path]
            if let url = segment.cursorURL { spelled["cursor_path"] = url.path }
            if let problem = segment.cursorProblem { spelled["cursor_problem"] = problem }
            return spelled
        }
    case .failure(let error):
        out["finish_error"] = error.localizedDescription
    case nil:
        break
    }
    window.close()
    return out
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: cursor_keys_proof host | run <work dir>\n".utf8))
    exit(2)
}
switch arguments[1] {
case "host":
    emit(hostFacts())
case "run" where arguments.count == 3:
    emit(run(URL(fileURLWithPath: arguments[2], isDirectory: true)))
default:
    FileHandle.standardError.write(Data("usage: cursor_keys_proof host | run <work dir>\n".utf8))
    exit(2)
}
