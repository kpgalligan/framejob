import AppKit

#if FRAMEJOB_DEV_TOOLS
/// `land_recording`'s camera (road map "creator-jobs" CO8, spec §11 CO-83 (c)): a fixture camera
/// file landed beside the screen segment's movie, as a recording's `(Camera).mov` lands, with
/// `camera_offset`, `camera_layout` and `camera_cutout` — so `co8_proof.py` can watch the layout
/// and the cutout at landing without a camera. A file of its own so the base file stays under
/// the 400-line cap. The refusals are argument checks, read after the polish's and before any
/// file is probed but the camera's; the place checks are `record_screen`'s own
/// (`recordingCameraLanding`).
extension AgentServer {
    /// The camera half of a fixture segment.
    struct LandRecordingCamera {
        let descriptor: MediaDescriptor
        let offset: Ticks
        let layout: RecordingCameraLayout
        let cutout: Bool
    }

    /// The fixed camera id a fixture recording's choice names: any non-nil id says "recorded
    /// with a camera beside the screen".
    static let landRecordingCameraID = "land_recording"

    /// `camera` (only with `movie`) and the three only with `camera`, each refused by name; then
    /// the layout and cutout through `recordingCameraLanding(a, place:)`; then the camera file
    /// probed. nil without `camera`.
    func landRecordingCamera(_ a: [String: Any], movie: String?, place: Bool) throws
        -> LandRecordingCamera?
    {
        let camera = try stringArg(a, "camera")
        if camera != nil, movie == nil {
            throw ToolError(
                message: "camera cannot be given without movie — a camera lands beside the "
                    + "screen segment's movie.")
        }
        for name in ["camera_offset", "camera_layout", "camera_cutout"]
        where a[name] != nil && !(a[name] is NSNull) && camera == nil {
            throw ToolError(
                message: "\(name) cannot be given without camera — it applies to the camera's "
                    + "clips.")
        }
        let offset = try intArg(a, "camera_offset") ?? 0
        let landing = try recordingCameraLanding(a, place: place)
        guard let camera else { return nil }
        return LandRecordingCamera(
            descriptor: try landRecordingProbe(camera), offset: Ticks(offset),
            layout: landing.layout, cutout: landing.cutout)
    }

    /// The four camera properties `landRecordingTool()` merges into its schema.
    static let landRecordingCameraProperties: [String: Any] = [
        "camera": [
            "type": "string",
            "description": "with movie only: a movie landed as the segment's (Camera).mov beside "
                + "the screen, on the Camera track by the recording's own rules (spec CAM-10, "
                + "CO-80).",
        ],
        "camera_offset": [
            "type": "integer",
            "description": "with camera only: the segment's camera_offset in ticks, positive "
                + "when the camera began after the screen (default 0).",
        ],
        "camera_layout": [
            "type": "string", "enum": RecordingCameraLayout.allCases.map(\.rawValue),
            "description": "with camera only: record_screen's camera_layout (default "
                + "corner_square); needs place.",
        ],
        "camera_cutout": [
            "type": "boolean",
            "description": "with camera only: record_screen's camera_cutout (default false); "
                + "needs place.",
        ],
    ]
}
#endif
