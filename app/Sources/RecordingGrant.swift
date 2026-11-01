import AVFoundation
import AppKit

/// The grants a screen recording stands on — each grant's read, the step a
/// press takes, the pane URLs and the sentences — values a probe can call.
/// A pure move out of `RecordingSetup.swift` under road map "creator-jobs"
/// CU0a's toll U1; `RecordingSetup+Camera.swift` extends `RecordingGrant`
/// with the camera's grant.

// MARK: - The grants

/// Decision 4 (road map 3 §0): the PANEL asks for the grants, the tool never
/// does — the rule the speech grant's `canAsk` carried, for two grants.
/// What lives here is the READ of each grant, the STEP a press takes, the
/// pane URLs and the sentences — all pure: nothing here prompts or opens;
/// `CGRequestScreenCaptureAccess()`, `AVCaptureDevice.requestAccess` and
/// the pane's `NSWorkspace.open` are called by the recorder panel alone
/// (`RecorderPanelController+Grants.swift`), because a system prompt needs
/// a person in front of it. A press asks for Screen Recording ONCE and
/// opens the pane on every later press (spec §11 recording) — but only in
/// a launchd-owned launch: a shell-launched press always asks, because TCC
/// gives that prompt to the terminal (R0 q1). A denied or restricted
/// microphone opens its pane; `.notDetermined` asks.
///
/// **Both refusal sentences are COMPUTED, and end with `launchClause` when
/// it is non-empty** (R1 review, unjudged and upheld): R0 q1 measured that
/// a shell-launched Frame Job is attributed by TCC to the TERMINAL, so a
/// person who followed the pane sentence and granted Frame Job.app would have
/// granted the wrong application and be refused again with no way to tell
/// why. The pane sentence stays the PREFIX — `recording_proof.py` matches
/// on it — and the clause names the launching process's pid.
enum RecordingGrant {
    /// `CGPreflightScreenCaptureAccess()` — true when this PROCESS may
    /// capture. R0 q1: a shell-launched binary is attributed by TCC to the
    /// terminal, so from a proof this reads the terminal's grant, not the
    /// app's.
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// The pane sentence alone — the prefix of `screenRecordingRefusal`.
    static let screenRecordingPaneSentence =
        "Screen Recording is not granted to Frame Job. Turn it on in System Settings ▸ "
        + "Privacy & Security ▸ Screen & System Audio Recording, then relaunch."

    static var screenRecordingRefusal: String { screenRecordingPaneSentence + launchClause }

    /// Empty for an app launched by launchd (`open -a`, the Finder, the
    /// Dock — ppid 1, responsible for itself); otherwise the sentence that
    /// says whose grant this process is actually running under. `getppid()`
    /// is the cheapest true reading: R0 q1's `responsibility_get_pid_
    /// responsible_for_pid` is private API, and the parent is what TCC
    /// follows for a process launched from a shell.
    static var launchClause: String {
        let parent = getppid()
        guard parent != 1 else { return "" }
        return " This Frame Job was launched by another process (pid \(parent)), so the grant "
            + "that counts is that application's — the terminal's, for a shell launch; or "
            + "relaunch with open -a \"Frame Job\"."
    }

    /// `AVCaptureDevice.authorizationStatus(for: .audio)`. Read BEFORE any
    /// `AVCaptureDeviceInput` is made: that initializer auto-prompts on
    /// `.notDetermined`, which is exactly the prompt the tool may not put up.
    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// The status as the framework spells it, for a message a script can
    /// read — `Transcriber.name(of:)`'s shape.
    static func name(of status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    /// Names the status word and the one action that changes it: a
    /// `notDetermined` grant is asked for by pressing Record in the panel (the
    /// only place that may prompt), a denied or restricted one is turned on
    /// in System Settings. `launchClause` follows, on the same terms as the
    /// screen sentence's.
    static func microphoneRefusal(_ status: AVAuthorizationStatus) -> String {
        let head = "The microphone is not granted to Frame Job (status: \(name(of: status))). "
        switch status {
        case .notDetermined:
            return head + "Press Record in File ▸ New Recording… once to grant it." + launchClause
        default:
            return head + "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, "
                + "then relaunch." + launchClause
        }
    }

    // MARK: The step a press takes

    /// What a press of Record does about one grant: go on, put up the
    /// system prompt, or open System Settings at the grant's pane.
    enum Step: Equatable {
        case proceed
        case ask
        case openPane
    }

    /// True when launchd is the parent (`open -a`, the Finder, the Dock) —
    /// the reading `launchClause` makes, so the two cannot disagree.
    static var launchedByLaunchd: Bool { getppid() == 1 }

    /// Screen Recording: granted goes on; a shell launch always asks (its
    /// prompt is the terminal's, R0 q1, so `asked` means nothing there);
    /// a launchd-owned press that has asked before opens the pane; else ask.
    static func screenStep(granted: Bool, asked: Bool, launchedByLaunchd: Bool) -> Step {
        if granted { return .proceed }
        if !launchedByLaunchd { return .ask }
        if asked { return .openPane }
        return .ask
    }

    /// The microphone, when one is chosen: authorized goes on,
    /// `.notDetermined` asks, and denied, restricted or unknown opens the
    /// pane — the system never prompts twice for it.
    static func microphoneStep(_ status: AVAuthorizationStatus) -> Step {
        switch status {
        case .authorized: return .proceed
        case .notDetermined: return .ask
        case .denied, .restricted: return .openPane
        @unknown default: return .openPane
        }
    }

    /// System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording.
    static let screenRecordingPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    /// System Settings ▸ Privacy & Security ▸ Microphone.
    static let microphonePaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")

    /// System Settings ▸ Privacy & Security ▸ Camera (camera-recording CR1c).
    static let cameraPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")

    /// What a note adds once the pane has been opened.
    static let paneOpenedSentence = " System Settings is open at that pane."

    /// The screen note after the pane opened: the pane sentence stays the
    /// PREFIX, and `launchClause` stays last.
    static var screenRecordingOpenedNote: String {
        screenRecordingPaneSentence + paneOpenedSentence + launchClause
    }

    /// The microphone note after its pane opened: the refusal's head and
    /// fix, the opened sentence, then `launchClause`.
    static func microphoneOpenedNote(_ status: AVAuthorizationStatus) -> String {
        "The microphone is not granted to Frame Job (status: \(name(of: status))). "
            + "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, then relaunch."
            + paneOpenedSentence + launchClause
    }
}
