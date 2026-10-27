import AVFoundation
import AppKit

/// The camera's half of each landed segment of a screen recording with a
/// camera beside it (camera-recording CR3a, spec §11 CAM-9 (4), (7)): the
/// walker in `+Finishing.swift` hands each landed screen segment here after
/// its microphone, and the camera file is judged on its own — never the
/// screen's failure. `+CameraBeside.swift` is what wrote the file.
///
/// **What becomes of a segment's camera.** None armed (no camera, or one that
/// stopped on its own earlier): the segment as it was. A writer that failed:
/// that segment's `cameraProblem`, naming the file when it is on disk (the
/// microphone's rule). A writer that took no buffer: no camera, silently,
/// its file removed (CAM-3). Otherwise the file is probed: read, it is the
/// segment's `cameraDescriptor` at `cameraBesideOffset`; not read, its
/// `cameraProblem`. A segment whose frame watch could not go back on the
/// stream at its resume is placed by E1 and says so in its `cameraNote`
/// (CAM-9 (6)).
extension ScreenRecorder {
    /// Segment `index`'s camera half, on main: `landed` with the camera's
    /// three fields set, to `then`.
    func probeCameraBeside(
        _ done: Session, at index: Int, _ landed: RecordingSegment,
        then: @escaping (RecordingSegment) -> Void
    ) {
        guard let camera = done.segments[index].camera else { return then(landed) }
        let screenArrived = done.screenStart(of: index)
        let note = camera.watchFailure.map {
            "This segment's camera is placed by the screen's did-start, not its first frame: "
                + "the frame watch could not go back on the stream at the resume (\($0))."
        }
        func with(_ descriptor: MediaDescriptor?, _ problem: String?) -> RecordingSegment {
            let offset =
                descriptor == nil
                ? 0
                : Self.cameraBesideOffset(
                    cameraPTS: camera.pts, firstFrame: camera.firstFrame,
                    screenHost: camera.screenHost, cameraArrived: camera.startedAt,
                    screenArrived: screenArrived)
            return RecordingSegment(
                descriptor: landed.descriptor, micDescriptor: landed.micDescriptor,
                micOffset: landed.micOffset, startedAt: landed.startedAt,
                micProblem: landed.micProblem, cameraDescriptor: descriptor,
                cameraOffset: offset, cameraProblem: problem,
                cameraNote: descriptor == nil ? nil : note)
        }
        let path = camera.url.path
        let clause = FileManager.default.fileExists(atPath: path) ? " Its file is at \(path)." : ""
        if let failure = camera.failure { return then(with(nil, failure + clause)) }
        if camera.finished, !camera.wrote {
            try? FileManager.default.removeItem(at: camera.url)
            return then(with(nil, nil))
        }
        MediaImporter.probe(url: camera.url, mayAsk: done.mayAsk) { outcome in
            switch outcome {
            case .success(let descriptor):
                then(with(descriptor, nil))
            case .failure(let error):
                let why =
                    done.timedOut && !camera.finished
                    ? "The camera recording did not finish writing within "
                        + "\(Int(Self.finishCeiling)) s."
                    : "The camera recording could not be read: " + error.localizedDescription
                then(with(nil, why + clause))
            }
        }
    }

    // MARK: - The offset (CAM-9 (4))

    /// The camera's start minus the screen's, in ticks: the camera's first
    /// buffer's PTS on the host clock minus E2 (`firstFrame`), else minus E1
    /// (`screenHost`, the did-start's arrival on the host clock); without
    /// both host stamps, the first buffer's arrival minus the screen's start
    /// (`Session.screenStart(of:)`); without those, 0. POSITIVE means the
    /// camera began after the screen.
    static func cameraBesideOffset(
        cameraPTS: Double?, firstFrame: Double?, screenHost: Double?,
        cameraArrived: Date?, screenArrived: Date?
    ) -> Ticks {
        var seconds: Double = 0
        if let cameraPTS, let screen = firstFrame ?? screenHost {
            seconds = cameraPTS - screen
        } else if let cameraArrived, let screenArrived {
            seconds = cameraArrived.timeIntervalSince(screenArrived)
        }
        return Ticks((seconds * Double(ReelTime.perSecond)).rounded())
    }
}
