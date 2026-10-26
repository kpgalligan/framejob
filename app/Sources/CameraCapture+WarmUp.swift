import AVFoundation

/// CAM-3's warm-up rule and the type of its facts (camera-recording CR2-0,
/// spec §11 CAM-3): the run, the tolerance and the bound, `isSteady`, and
/// `WarmUp` with its `note`, moved out of `CameraCapture.swift` at the
/// 400-line cap as a pure move. The warm-up's running state (`Warming`,
/// `warmUpBuffer`, `endWarmUp`) stays in `CameraCapture.swift`, because it
/// is private stored state.
extension CameraCapture {
    /// CAM-3's warm-up: five intervals in a row within 15 % of the frame
    /// duration (a cold interval is 30 % long; the spike's steady stream
    /// never passed 5 %), bounded at 1 s.
    static let warmUpRun = 5
    static let warmUpTolerance = 0.15
    static let warmUpBound: TimeInterval = 1.0

    /// What the warm-up waited for: its length from the session's start,
    /// the buffers seen, whether the stream reached the format's rate, the
    /// rate it ran at over the buffers seen, and their intervals in ms.
    struct WarmUp: Equatable {
        let seconds: Double
        let buffers: Int
        let steady: Bool
        let rate: Double
        let wanted: Double
        let intervals: [Double]

        /// The result's `camera.note` when the bound passed first; nil when
        /// the stream was steady.
        var note: String? {
            guard !steady else { return nil }
            let bound = String(format: "%g", CameraCapture.warmUpBound)
            guard rate > 0 else {
                return "The camera delivered no steady frames in the \(bound) s it was given to "
                    + "settle; the recording began anyway."
            }
            return String(format: "The camera ran at %.1f fps, not its %g, ", rate, wanted)
                + "in the \(bound) s it was given to settle; the recording began anyway."
        }
    }

    /// Whether one frame interval is on the format's rate (CAM-3).
    static func isSteady(_ interval: Double, frame: Double) -> Bool {
        abs(interval - frame) <= frame * warmUpTolerance
    }
}
