import AVFoundation
import AppKit
import ScreenCaptureKit

/// `record_screen`'s ARGUMENT vocabulary and the lookup the arguments meet —
/// the second cut off `AgentServer+Recording.swift` (R1 review; the first is
/// `+RecordingResult.swift`), taken when the fixes put that file at 481
/// lines against the 400-line cap for a new file. The seam is the sentence
/// its header had used to describe itself: "the wait around the recorder
/// and the argument vocabulary in front of it" — the wait stayed, the
/// vocabulary came here, and with it the shareable-content call and the
/// display ordering, because they are what the `display` and `window`
/// arguments RESOLVE against and nothing else reads them. Every function is
/// pure in the arguments, or a wait on one framework answer; none touches
/// the recorder. `private` → internal is the whole cost.
///
/// **The refusal ORDER is decided in the caller**, `recordScreen`, which
/// calls these in the order the header there fixes: the caller's own
/// mistakes, the grant, the lookup. Nothing here reads a grant.
extension AgentServer {

    // MARK: - The arguments

    /// `source`: what is recorded — the screen (the default) or the
    /// microphone alone (the panel's Microphone Only, spec §11 recording).
    enum RecordingSourceKind: String, CaseIterable {
        case screen
        case voiceOver = "voice_over"
    }

    /// The arguments a voice-over refuses by name: everything that only a
    /// picture or the stream reads.
    static let voiceOverScreenOnlyArguments = ["display", "window", "system_audio", "show_clicks", "size"]

    /// `source`, default `screen`; an unknown value refused with the
    /// vocabulary. For `voice_over`, the screen-only arguments the caller
    /// GAVE (a JSON null is not given, `scalarArg`'s rule) are refused
    /// together, in `voiceOverScreenOnlyArguments` order, then
    /// `microphone: false`.
    func recordingSourceKind(_ a: [String: Any]) throws -> RecordingSourceKind {
        guard let name = try stringArg(a, "source") else { return .screen }
        guard let kind = RecordingSourceKind(rawValue: name) else {
            let known = RecordingSourceKind.allCases.map { $0.rawValue }
            throw ToolError(
                message: "source must be one of " + known.joined(separator: ", ")
                    + " (got \"\(name)\").")
        }
        guard kind == .voiceOver else { return kind }
        let strangers = Self.voiceOverScreenOnlyArguments.filter { a[$0] != nil && !(a[$0] is NSNull) }
        guard strangers.isEmpty else {
            throw ToolError(
                message: "With source voice_over, " + strangers.joined(separator: ", ")
                    + " cannot be given — a voice-over records the microphone alone.")
        }
        if try boolArg(a, "microphone") == false {
            throw ToolError(
                message: "With source voice_over, microphone cannot be false — a voice-over "
                    + "records the microphone alone.")
        }
        return kind
    }

    /// `seconds`: required, 1…600. Spelled back as the caller sent it (`0`,
    /// not `0.0`) when it is whole.
    func recordingSeconds(_ a: [String: Any]) throws -> Double {
        guard let seconds = try doubleArg(a, "seconds") else {
            throw ToolError(message: "Missing required argument: seconds")
        }
        guard seconds >= 1, seconds <= 600 else {
            let whole = seconds == seconds.rounded() && abs(seconds) < 1e15
            let spelled = whole ? String(Int(seconds)) : String(seconds)
            throw ToolError(message: "seconds must be 1…600 (got \(spelled)).")
        }
        return seconds
    }

    /// `display` (an index, default 0) and `window` (a CGWindowID), at most
    /// one; the index meets the LIST later, once it can be asked for.
    func recordingSourceArguments(_ a: [String: Any]) throws -> (Int, CGWindowID?) {
        let display = try intArg(a, "display")
        let window = try intArg(a, "window")
        guard display == nil || window == nil else {
            throw ToolError(
                message: "Pass display or window, not both — a recording is of one or the other.")
        }
        if let display, display < 0 {
            throw ToolError(message: "display must be 0 or more (got \(display)).")
        }
        var windowID: CGWindowID?
        if let window {
            guard window >= 0, window <= Int(CGWindowID.max) else {
                throw ToolError(message: "window must be a CGWindowID (got \(window)).")
            }
            windowID = CGWindowID(window)
        }
        return (display ?? 0, windowID)
    }

    /// `size`: `nominal` (default) or `best`, `requestedFrameFormat`'s form.
    func recordingResolution(_ a: [String: Any]) throws -> RecordingResolution {
        guard let name = try stringArg(a, "size") else { return .nominal }
        guard let resolution = RecordingResolution(rawValue: name.lowercased()) else {
            let known = RecordingResolution.allCases.map { $0.rawValue }
            throw ToolError(
                message: "size must be one of " + known.joined(separator: ", ")
                    + " (got \"\(name)\").")
        }
        return resolution
    }

    /// `path`, the FOLDER: trimmed, tilde-expanded, and an empty or blank
    /// string counting as absent — `RecordingFiles.folder()` then applies —
    /// because `URL(fileURLWithPath: "")` is the process's working directory,
    /// and a recording written into whatever `cwd` the app was launched
    /// from is a file nobody can find.
    func recordingFolder(_ a: [String: Any]) throws -> URL? {
        guard let raw = try stringArg(a, "path") else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(
            fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Where the recording will land, decided BEFORE it starts. A named
    /// `project` goes through `target(_:)` and its refusal stands; no name
    /// and no document is `.newProject`; otherwise the frontmost. Main.
    func recordingDestination(_ a: [String: Any]) throws -> RecordingDestination {
        if try stringArg(a, "project") != nil {
            return .document(recipeKey: try target(a).recipeKey)
        }
        if openProjects().isEmpty { return .newProject }
        return .document(recipeKey: try target(a).recipeKey)
    }

    // MARK: - The content

    /// `ScreenRecorder.shareableContent`, CALLED from this thread (the helper
    /// issues the framework call from a global queue and hops the completion
    /// to main whatever thread asks) and waited for here. Not through
    /// `onMain`: on a locked console the framework held the calling thread
    /// ~37 s before answering nothing — main's, through a hop.
    func shareableContent() throws -> SCShareableContent {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AgentBox<Result<SCShareableContent, Error>>()
        ScreenRecorder.shareableContent { outcome in
            box.value = outcome
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 20) == .success else {
            throw ToolError(message: "Timed out listing the shareable displays and windows.")
        }
        switch box.value {
        case .success(let content): return content
        case .failure(let error): throw ToolError(message: error.localizedDescription)
        case nil:
            throw ToolError(message: "The shareable displays and windows could not be listed.")
        }
    }

    /// The shareable displays, MAIN first — so `display` 0 means what the
    /// catalog says whatever order the framework lists them in.
    static func orderedDisplays(_ content: SCShareableContent) -> [SCDisplay] {
        let main = CGMainDisplayID()
        return content.displays.filter { $0.displayID == main }
            + content.displays.filter { $0.displayID != main }
    }

    /// The source the two arguments name. A window id naming nothing
    /// shareable is refused by `ScreenRecorder.filter(for:in:)`'s sentence.
    /// An EMPTY display list is a fact about the host — the console is
    /// locked or every display is asleep (measured: a true preflight and
    /// zero displays, the night the proof was written) — and is named as
    /// that, BEFORE the range sentence, which would otherwise read
    /// "display must be 0…0 (got 0)" for a caller who asked for nothing odd.
    func recordingSource(
        _ displayIndex: Int, _ windowID: CGWindowID?, in content: SCShareableContent
    ) throws -> RecordingSource {
        if let windowID { return .window(windowID) }
        let displays = Self.orderedDisplays(content)
        guard !displays.isEmpty else {
            throw ToolError(
                message: "No display is shareable right now — the console is locked or every "
                    + "display is asleep; nothing can be recorded until one is.")
        }
        guard displayIndex < displays.count else {
            throw ToolError(
                message: "display must be 0…\(displays.count - 1) (got \(displayIndex)); "
                    + "\(displays.count) display\(displays.count == 1 ? " is" : "s are") "
                    + "shareable.")
        }
        return .display(displays[displayIndex].displayID)
    }
}
