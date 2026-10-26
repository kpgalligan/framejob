import AVFoundation
import AppKit

/// `record_screen`'s CAMERA (camera-recording CR1b, spec §11 CAM-4): the
/// `camera` argument, the arguments a camera recording refuses, which
/// connected camera a call means and whether the Camera grant is held, and
/// what the answer says about the camera. A file of its own because
/// `+Recording.swift` and `+RecordingResult.swift` stand near the 400-line
/// cap; `+RecordingArguments.swift` is the model — every function here is
/// pure in its arguments, or one `onMain` hop that reads the framework's
/// answers and hands them to a pure one.
///
/// **The order is CAM-3's**, decided in the callers: `recordingSourceKind`
/// calls `recordingCameraStrangers` right after `source`'s value (step 3),
/// and `recordScreen` calls `recordingCamera` after the `project` (steps 7
/// and 8): the lookup needs no grant, so an unknown name is answered as
/// that whatever the grant says, and only then is the Camera grant read.
/// Nothing here asks for it: the grant is READ (`RecordingGrant.cameraStatus`)
/// and a missing one is refused by `RecordingGrant.cameraRefusal`'s
/// sentence; the panel is where a person grants (recording.md decision 4).
/// `ScreenRecorder.startCamera` reads it again, its own guard.
extension AgentServer {

    /// The arguments a camera recording refuses by name (CAM-4 point 3),
    /// in the order the refusal lists them: everything only a screen's
    /// picture or stream reads, and `rate` — a camera records at its own
    /// format's rate.
    static let cameraRefusedArguments = [
        "display", "window", "system_audio", "show_clicks", "size", "include_framejob_windows",
        "rate",
    ]

    /// `camera` (CAM-4 point 1): a device's `uniqueID` or name, trimmed; nil
    /// when absent, a JSON null, or blank — absent takes the default camera.
    /// A value that is not a string is `stringArg`'s refusal.
    func recordingCameraArgument(_ a: [String: Any]) throws -> String? {
        guard let raw = try stringArg(a, "camera") else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// CAM-4 points 2 and 3, called by `recordingSourceKind` right after
    /// `source`'s value: with any source but `camera`, a given `camera` is
    /// refused; with `camera`, the given ones of `cameraRefusedArguments`
    /// (a JSON null is not given, `scalarArg`'s rule) are refused together,
    /// in that order.
    func recordingCameraStrangers(_ a: [String: Any], kind: RecordingSourceKind) throws {
        let camera = try recordingCameraArgument(a)
        guard kind == .camera || camera == nil else {
            throw ToolError(
                message: "With source \(kind.rawValue), camera cannot be given — only source "
                    + "camera records a camera.")
        }
        guard kind == .camera else { return }
        let strangers = Self.cameraRefusedArguments.filter { a[$0] != nil && !(a[$0] is NSNull) }
        guard strangers.isEmpty else {
            throw ToolError(
                message: "With source camera, " + strangers.joined(separator: ", ")
                    + " cannot be given — a camera recording records the camera alone, at the "
                    + "camera's own format.")
        }
    }

    /// CAM-3 (7) then (8), pure: the camera `wanted` names
    /// (`CameraDevices.match`), or the default (`CameraDevices.defaultIndex`)
    /// when it is nil — "No camera is connected." when none is, a sentence
    /// naming every camera present when the name or id is unknown — and only
    /// then the grant, `status`, refused by `RecordingGrant.cameraRefusal`
    /// unless `.authorized`. The chosen camera's `uniqueID`.
    static func recordingCameraID(
        _ wanted: String?, in cameras: [CameraDeviceFacts], preferredID: String?,
        status: AVAuthorizationStatus
    ) throws -> String {
        let index: Int?
        if let wanted {
            index = CameraDevices.match(wanted, in: cameras)
        } else {
            index = CameraDevices.defaultIndex(in: cameras, preferredID: preferredID)
        }
        guard let index else {
            throw ToolError(
                message: wanted.map { CameraDevices.noSuchCameraSentence($0, cameras: cameras) }
                    ?? CameraDevices.noCameraSentence)
        }
        guard status == .authorized else {
            throw ToolError(message: RecordingGrant.cameraRefusal(status))
        }
        return cameras[index].uniqueID
    }

    /// SERVER THREAD. `recordingCameraID` over what the framework says now,
    /// read in ONE `onMain` hop: the connected cameras' facts (listing opens
    /// nothing and needs no grant), the system's preferred camera and the
    /// Camera grant's status — read, never asked.
    func recordingCamera(_ a: [String: Any]) throws -> String {
        let wanted = try recordingCameraArgument(a)
        return try onMain {
            try Self.recordingCameraID(
                wanted, in: CameraDevices.connected().map(CameraDevices.facts(of:)),
                preferredID: AVCaptureDevice.systemPreferredCamera?.uniqueID,
                status: RecordingGrant.cameraStatus)
        }
    }

    /// The answer's `camera` object (CAM-4 point 6): `name`, `id` (the
    /// chosen device's `uniqueID`, the choice's `camera`), `format` (as
    /// `CameraDevices.spelled` writes it), and `problem` and `note` only
    /// when set.
    static func cameraFields(_ camera: RecordingCamera, id: String?) -> [String: Any] {
        var fields: [String: Any] = ["name": camera.name, "format": camera.format]
        if let id { fields["id"] = id }
        if let problem = camera.problem { fields["problem"] = problem }
        if let note = camera.note { fields["note"] = note }
        return fields
    }
}
