import AVFoundation
import AppKit

/// A camera recording's half of `RecordingSetup.swift` (camera-recording
/// CR1a, spec §11 CAM-3): its file stem and its grant's read and refusal;
/// and the panel's step for the grant and the note once its pane is open
/// (CR1c, CAM-5; the pane's URL is `RecordingSetup.swift`'s, beside the
/// others, the one file a System Settings URL is spelled in). Values a probe
/// can call, in a file of their own because `RecordingSetup.swift` stands
/// near the 400-line cap. Nothing here
/// prompts: `AVCaptureDevice.requestAccess(for: .video)` is the recorder
/// panel's alone (`RecorderPanelController+Grants.swift`), and `cameraStatus`
/// is read before any `AVCaptureDeviceInput` exists, because that
/// initializer prompts on `.notDetermined`.

extension RecordingFiles {
    /// `Camera Recording 2026-10-26 at 17.14.33` — a camera recording's file,
    /// `stem(at:)`'s spelling and pinning with its own lead words, as
    /// `voiceOverStem(at:)` is.
    static func cameraStem(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "'Camera Recording' yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }
}

extension RecordingGrant {
    /// `AVCaptureDevice.authorizationStatus(for: .video)`, read BEFORE any
    /// `AVCaptureDeviceInput` is made, `microphoneStatus`'s rule. A
    /// shell-launched process reads its responsible process's grant (the
    /// terminal's, road map 3 R0 q1).
    static var cameraStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// `microphoneRefusal`'s shape: the status word, then the one action
    /// that changes it — a `notDetermined` grant is asked for by pressing
    /// Record with the Camera source (the panel, CR1c: the only place that
    /// may prompt), any other is turned on in System Settings — then
    /// `launchClause`.
    static func cameraRefusal(_ status: AVAuthorizationStatus) -> String {
        let head = "The camera is not granted to Frame Job (status: \(name(of: status))). "
        switch status {
        case .notDetermined:
            return head
                + "Press Record with the Camera source in File ▸ New Recording… once to grant it."
                + launchClause
        default:
            return head + "Turn it on in System Settings ▸ Privacy & Security ▸ Camera, "
                + "then relaunch." + launchClause
        }
    }

    /// The camera, for a press with Source Camera: `microphoneStep`'s
    /// mapping — authorized goes on, `.notDetermined` asks, any other opens
    /// the pane.
    static func cameraStep(_ status: AVAuthorizationStatus) -> Step {
        switch status {
        case .authorized: return .proceed
        case .notDetermined: return .ask
        case .denied, .restricted: return .openPane
        @unknown default: return .openPane
        }
    }

    /// The camera note after its pane opened: the refusal's head and fix,
    /// the opened sentence, then `launchClause`.
    static func cameraOpenedNote(_ status: AVAuthorizationStatus) -> String {
        "The camera is not granted to Frame Job (status: \(name(of: status))). "
            + "Turn it on in System Settings ▸ Privacy & Security ▸ Camera, then relaunch."
            + paneOpenedSentence + launchClause
    }
}
