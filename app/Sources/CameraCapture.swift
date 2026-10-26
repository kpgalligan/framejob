import AVFoundation
import AppKit

/// One camera, captured to one `AVAssetWriter` per SEGMENT (camera-recording
/// CR1a, spec §11 CAM-2's verdict and CAM-3): an `AVCaptureSession` with the
/// device's input and an `AVCaptureVideoDataOutput`, whose buffers are
/// appended to the writer armed for the current segment. Pause is
/// `endSegment` and resume `beginSegment` on the one running session (CR0's
/// P2: the next writer's first buffer 1–33 ms after the call). The measured
/// reference is `tools/proof/camera_spike/camera_spike_probe.swift`'s
/// `SpikeCamera`, `spikeMakeWriter` and `spikeFinishWriter`.
///
/// **The format is held.** macOS has no `.inputPriority` preset, so a session
/// may re-take the device's format when it starts: the device is locked for
/// configuration in `init`, the format and both frame durations (its maximum
/// rate, `spikeApplyFormat`'s lock) are set under the lock, set AGAIN once
/// `startRunning` returns, and the lock is let go only after
/// `stopRunning` (CR0's carry-over; its owner run kept the format with the
/// format set again).
///
/// **Two queues of its own**, the one exception to the recorder's no-queue
/// rule, both forced by the framework: `startRunning` and `stopRunning` block
/// their caller, so they run on `sessionQueue`; and a data output delivers
/// its buffers on a serial queue it is given, `sampleQueue`, which alone
/// touches the armed writer — `beginSegment` and `endSegment` hand their
/// writer to it, so the appends need no lock. Every report to the machine
/// is stamped where it arrives and hopped to main: `start`'s completion,
/// `onSegmentStarted`, `endSegment`'s completion and `onStoppedOnItsOwn`.
///
/// **The stream is warm before the first segment** (spec §11 CAM-3's
/// warm-up): a cold camera's first frames come slower than its rate, so
/// `start`'s completion waits until `warmUpRun` consecutive frame intervals,
/// by PTS, are each within `warmUpTolerance` of the format's frame duration,
/// bounded at `warmUpBound` from the session's start, past which it
/// completes anyway and `warmUp.note` names the rate measured; the rule's
/// constants, `isSteady` and `WarmUp` live in `CameraCapture+WarmUp.swift`.
/// No writer is armed while it waits; a resume, on the running session,
/// does not wait.
///
/// **Late frames are kept** (`alwaysDiscardsLateVideoFrames = false`) and
/// the device's native pixel format is left alone; a buffer the writer is
/// not ready for is dropped and counted. Each writer is
/// `expectsMediaDataInRealTime` and its session starts at its first buffer's
/// PTS; HEVC where the writer can apply it at the format's size, else H.264.
final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    /// The format asked for and recorded at; every file is written at its size.
    let applied: CameraFormatFacts
    let session = AVCaptureSession()
    private let device: AVCaptureDevice
    private let format: AVCaptureDevice.Format
    private let frameDuration: CMTime?
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.kgalligan.FrameJob.camera.session")
    private let sampleQueue = DispatchQueue(label: "com.kgalligan.FrameJob.camera.samples")
    private var holding = false
    private var stopped = false
    private var observers: [NSObjectProtocol] = []

    /// One segment's writer as `sampleQueue` holds it. `failure` is a writer
    /// that could not be made: nothing is appended and `endSegment` says so.
    private struct Armed {
        let url: URL
        let writer: AVAssetWriter?
        let input: AVAssetWriterInput?
        let failure: String?
        var started = false
    }
    /// `sampleQueue` only.
    private var armed: Armed?
    /// `sampleQueue` only: buffers dropped because the writer was not ready.
    private var notReady = 0

    /// The warm-up in progress, `sampleQueue` only; nil once it ended.
    private struct Warming {
        let since: Date
        let frame: Double
        let completion: (Error?) -> Void
        var firstPTS: Double?
        var lastPTS: Double?
        var buffers = 0
        var run = 0
        var intervals: [Double] = []
    }
    private var warming: Warming?
    /// MAIN THREAD. The warm-up `start` waited for, set before its
    /// completion; nil for a format with no frame duration.
    private(set) var warmUp: WarmUp?

    /// Main. The writer's first buffer: the segment's file, its PTS on the
    /// host clock in seconds (NaN when the conversion failed) and its
    /// arrival.
    var onSegmentStarted: ((URL, _ firstPTS: Double, _ arrived: Date) -> Void)?
    /// Main. The session stopped without being asked — a runtime error, an
    /// interruption, the device disconnected — with the sentence to say.
    var onStoppedOnItsOwn: ((String) -> Void)?

    /// MAIN THREAD. Builds the session for `device` at `formats[format]` and
    /// takes the configuration lock. Throws `RecorderError.cameraDevice` for
    /// an index the device lacks, an input or output the session will not
    /// take, or a lock it will not give. The caller has read the Camera
    /// grant: `AVCaptureDeviceInput(device:)` prompts on `.notDetermined`.
    init(device: AVCaptureDevice, format index: Int) throws {
        guard device.formats.indices.contains(index) else {
            throw RecorderError.cameraDevice(
                "The camera \(device.localizedName) has no format \(index).")
        }
        self.device = device
        format = device.formats[index]
        applied = CameraDevices.facts(of: device).formats[index]
        frameDuration =
            format.videoSupportedFrameRateRanges
            .max { $0.maxFrameRate < $1.maxFrameRate }?.minFrameDuration
        super.init()
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw RecorderError.cameraDevice(
                "The camera \(device.localizedName) cannot be opened: "
                    + error.localizedDescription)
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        output.alwaysDiscardsLateVideoFrames = false
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError.cameraDevice(
                "The camera \(device.localizedName) cannot be recorded from.")
        }
        session.addInput(input)
        session.addOutput(output)
        do {
            try device.lockForConfiguration()
        } catch {
            throw RecorderError.cameraDevice(
                "The camera \(device.localizedName) could not be configured: "
                    + error.localizedDescription)
        }
        holding = true
        applyFormat()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CameraCapture does not support NSCoder")
    }

    /// Under the held lock: the format, and both frame durations at its
    /// maximum rate.
    private func applyFormat() {
        if device.activeFormat != format { device.activeFormat = format }
        if let frameDuration {
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
        }
    }

    /// Starts the session on `sessionQueue`, the format and both frame
    /// durations set again once it runs; `completion` on main, nil once the
    /// stream is warm (or the bound passed), an error when it did not run.
    func start(completion: @escaping (Error?) -> Void) {
        observe()
        sessionQueue.async { [self] in
            session.startRunning()
            if session.isRunning { applyFormat() }
            guard session.isRunning else {
                return DispatchQueue.main.async {
                    completion(
                        RecorderError.cameraDevice(
                            "The camera \(self.device.localizedName) did not start."))
                }
            }
            guard let frame = frameDuration?.seconds, frame > 0 else {
                return DispatchQueue.main.async { completion(nil) }
            }
            sampleQueue.async { [self] in
                warming = Warming(since: Date(), frame: frame, completion: completion)
                sampleQueue.asyncAfter(deadline: .now() + Self.warmUpBound) { [self] in
                    endWarmUp(steady: false)
                }
            }
        }
    }

    /// `sampleQueue`. One buffer of the warm-up: its interval counted toward
    /// the run, which ends the warm-up at `warmUpRun`.
    private func warmUpBuffer(_ buffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        guard pts.isValid, var current = warming else { return }
        if let last = current.lastPTS {
            let interval = pts.seconds - last
            current.intervals.append((interval * 10_000).rounded() / 10)
            current.run = Self.isSteady(interval, frame: current.frame) ? current.run + 1 : 0
        } else {
            current.firstPTS = pts.seconds
        }
        current.lastPTS = pts.seconds
        current.buffers += 1
        warming = current
        if current.run >= Self.warmUpRun { endWarmUp(steady: true) }
    }

    /// `sampleQueue`, once: the warm-up's facts to main, then `start`'s
    /// completion. The next buffer is the first a segment's writer can take.
    private func endWarmUp(steady: Bool) {
        guard let done = warming else { return }
        warming = nil
        let span = (done.lastPTS ?? 0) - (done.firstPTS ?? 0)
        let facts = WarmUp(
            seconds: Date().timeIntervalSince(done.since), buffers: done.buffers, steady: steady,
            rate: done.buffers > 1 && span > 0 ? Double(done.buffers - 1) / span : 0,
            wanted: applied.maxRate, intervals: done.intervals)
        DispatchQueue.main.async { [self] in
            warmUp = facts
            done.completion(nil)
        }
    }

    // MARK: - Segments

    /// MAIN THREAD. Arms a writer for `url`; it starts at the next buffer.
    func beginSegment(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        var armed: Armed
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            func settings(_ codec: AVVideoCodecType) -> [String: Any] {
                [AVVideoCodecKey: codec, AVVideoWidthKey: applied.width,
                 AVVideoHeightKey: applied.height]
            }
            let codec: AVVideoCodecType =
                writer.canApply(outputSettings: settings(.hevc), forMediaType: .video)
                ? .hevc : .h264
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings(codec))
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw RecorderError.cameraDevice("The camera's writer would not take its input.")
            }
            writer.add(input)
            guard writer.startWriting() else {
                throw writer.error
                    ?? RecorderError.cameraDevice("The camera's writer did not start.")
            }
            armed = Armed(url: url, writer: writer, input: input, failure: nil)
        } catch {
            armed = Armed(
                url: url, writer: nil, input: nil,
                failure: "The camera's file could not be written: " + error.localizedDescription)
        }
        sampleQueue.async { [self] in self.armed = armed }
    }

    /// MAIN THREAD. Closes the armed writer; `completion` on main. A writer
    /// that took no buffer is cancelled, its file removed, and answers
    /// `wrote` false; one that did is finished and answers `wrote` true with
    /// the writer's failure, if any.
    func endSegment(completion: @escaping (_ wrote: Bool, _ failure: String?) -> Void) {
        sampleQueue.async { [self] in
            let closing = armed
            armed = nil
            guard let closing else {
                return DispatchQueue.main.async { completion(false, nil) }
            }
            guard let writer = closing.writer, let input = closing.input, closing.started else {
                closing.writer?.cancelWriting()
                try? FileManager.default.removeItem(at: closing.url)
                return DispatchQueue.main.async { completion(false, closing.failure) }
            }
            input.markAsFinished()
            writer.finishWriting {
                let failure =
                    writer.status == .completed
                    ? nil
                    : "The camera recording failed: "
                        + (writer.error?.localizedDescription ?? "its writer did not complete.")
                DispatchQueue.main.async { completion(true, failure) }
            }
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let arrived = Date()
        if warming != nil { return warmUpBuffer(sampleBuffer) }
        guard var current = armed, let writer = current.writer, let input = current.input
        else { return }
        if !current.started {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: pts)
            current.started = true
            armed = current
            let host = Self.hostSeconds(pts, from: session.synchronizationClock) ?? .nan
            let url = current.url
            DispatchQueue.main.async { [weak self] in
                self?.onSegmentStarted?(url, host, arrived)
            }
        }
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        } else {
            notReady += 1
        }
    }

    /// `time` on the host clock, in seconds; nil when it cannot be converted.
    static func hostSeconds(_ time: CMTime, from clock: CMClock?) -> Double? {
        guard time.isValid, let clock else { return nil }
        let converted = CMSyncConvertTime(time, from: clock, to: CMClockGetHostTimeClock())
        return converted.isValid ? converted.seconds : nil
    }

    // MARK: - Stopping

    /// MAIN THREAD, idempotent. Stops listening, then on `sessionQueue`
    /// stops the session and lets the configuration lock go.
    func stop() {
        guard !stopped else { return }
        stopped = true
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
            if holding {
                device.unlockForConfiguration()
                holding = false
            }
        }
    }

    /// The three ways a session stops on its own, each hopped to main and
    /// reported once, never after `stop()`.
    private func observe() {
        let center = NotificationCenter.default
        let name = device.localizedName
        func report(_ sentence: String) {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped else { return }
                self.onStoppedOnItsOwn?(sentence)
            }
        }
        observers = [
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
            ) { note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                report(
                    "The camera \(name) stopped on its own: "
                        + (error?.localizedDescription ?? "the session reported a runtime error."))
            },
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
            ) { _ in
                report("The camera \(name) stopped on its own: its session was interrupted.")
            },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil
            ) { _ in
                report("The camera \(name) stopped on its own: it was disconnected.")
            },
        ]
    }
}
