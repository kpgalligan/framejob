import AVFoundation
import AppKit

/// The microphone half of `ScreenRecorder`: the capture session that writes
/// the second file (R0 q2), prepared AHEAD of the recording, and the meter
/// that reads it. Cut out of `ScreenRecorder.swift` along the line the
/// header there names — the machine in one file, the device in this one —
/// when the preparation took the base file past the 400-line cap.
///
/// **Why prepare** (R1 review, unjudged and upheld by a −421 ms smoke run:
/// the first 0.4 s of voice was simply not in the file). `AVCaptureSession.
/// startRunning()` costs 100–400 ms on first use, and a session started
/// inside `start` pays it after the countdown has ended, so the microphone
/// is deaf for the recording's first words. `prepareMicrophone` builds the
/// session and starts it while the countdown still runs; `start` ADOPTS it
/// when its device is the choice's and builds one otherwise; a refused
/// start and every conclude tear it down, so an input never stays open
/// past the recording it was for. Never a prompt: the status is read before
/// `AVCaptureDeviceInput(device:)` is made, `start`'s own rule.
extension ScreenRecorder {
    /// A running session waiting for a `start` whose choice names its device.
    struct PreparedMicrophone {
        let deviceID: String
        let session: AVCaptureSession
        let output: AVCaptureAudioFileOutput
    }

    /// What one recording's microphone is: the session, its file output and
    /// the `.m4a` beside the movie.
    typealias MicrophoneCapture = (
        session: AVCaptureSession, output: AVCaptureAudioFileOutput, url: URL
    )

    // MARK: - Preparation

    /// MAIN THREAD, idle only. A nil id, a status other than `.authorized`,
    /// an id no connected device carries, or a session that will not run
    /// does nothing and leaves nothing behind; the same device already
    /// prepared and running is kept. Blocks main for the session's start
    /// (100–180 ms measured, R0 q6b) — the point is to spend it now.
    func prepareMicrophone(_ deviceID: String?) {
        guard state == .idle, let id = deviceID, RecordingGrant.microphoneStatus == .authorized,
            let device = Self.microphone(withID: id)
        else { return }
        if let prepared = preparedMicrophone, prepared.deviceID == id, prepared.session.isRunning {
            return
        }
        discardPreparedMicrophone()
        guard let built = try? Self.microphoneSession(for: device) else { return }
        built.session.startRunning()
        guard built.session.isRunning else { return }
        preparedMicrophone = PreparedMicrophone(
            deviceID: id, session: built.session, output: built.output)
    }

    /// MAIN THREAD. Stops and forgets a prepared session; a no-op without one.
    func discardPreparedMicrophone() {
        preparedMicrophone?.session.stopRunning()
        preparedMicrophone = nil
    }

    /// `start`'s microphone: the prepared session when its device is
    /// `device` and it is still running (a device that went away meanwhile
    /// stops its session), else a fresh one, which `start` will run. Either
    /// way the prepared slot is empty afterwards — adopted, or discarded
    /// because it was the wrong device.
    func microphoneCapture(for device: AVCaptureDevice, beside movie: URL) throws
        -> MicrophoneCapture
    {
        let url = RecordingFiles.microphoneURL(beside: movie)
        if let prepared = preparedMicrophone, prepared.deviceID == device.uniqueID,
            prepared.session.isRunning
        {
            preparedMicrophone = nil
            return (prepared.session, prepared.output, url)
        }
        discardPreparedMicrophone()
        let built = try Self.microphoneSession(for: device)
        return (built.session, built.output, url)
    }

    /// The capture session for the second file: the device's input and an
    /// `AVCaptureAudioFileOutput`, not yet running.
    private static func microphoneSession(for device: AVCaptureDevice) throws
        -> (session: AVCaptureSession, output: AVCaptureAudioFileOutput)
    {
        let capture = AVCaptureSession()
        let fileOutput = AVCaptureAudioFileOutput()
        let input = try AVCaptureDeviceInput(device: device)
        guard capture.canAddInput(input), capture.canAddOutput(fileOutput) else {
            throw RecorderError.microphoneDevice(
                "The microphone \(device.localizedName) cannot be recorded from.")
        }
        capture.addInput(input)
        capture.addOutput(fileOutput)
        return (capture, fileOutput)
    }

    // MARK: - The meter

    /// MAIN THREAD, from the panel's 30 Hz timer. Reads the microphone file
    /// output's connection channels and publishes one reading; a no-op —
    /// nothing published — while no microphone is recording, and once the
    /// microphone has finished or failed (finding 3 published the silence
    /// then, and a dead connection must not light the bar again). One
    /// channel is reported on both sides, `LevelMeterSink`'s rule for a
    /// mono track (R0 q6c: the connection exposes `averagePowerLevel` and
    /// `peakHoldLevel` in dB on every poll, so there is no sample buffer and
    /// no queue in it).
    func publishMicrophoneLevel() {
        guard state == .recording, let current = session, !current.micFinished,
            current.micFailure == nil, let output = current.micOutput,
            let connection = output.connection(with: .audio),
            let first = connection.audioChannels.first
        else { return }
        let second = connection.audioChannels.count > 1 ? connection.audioChannels[1] : first
        meter.publish(
            LevelMeterReading(
                peakLeft: RecordingMeter.linear(fromDecibels: first.peakHoldLevel),
                peakRight: RecordingMeter.linear(fromDecibels: second.peakHoldLevel),
                rmsLeft: RecordingMeter.linear(fromDecibels: first.averagePowerLevel),
                rmsRight: RecordingMeter.linear(fromDecibels: second.averagePowerLevel)),
            from: ObjectIdentifier(self))
    }
}
