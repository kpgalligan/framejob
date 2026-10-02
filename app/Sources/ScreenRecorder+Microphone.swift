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

    /// MAIN THREAD. Stops and forgets a prepared session, if there is one.
    /// While IDLE it also publishes silence (#98 c), prepared or not: the
    /// countdown's meter read the prepared session, and a cancel, a close,
    /// an abandoned or refused start and `failStart` (which idles first) all
    /// come here, so the bar never holds a level for an input that is closed.
    func discardPreparedMicrophone() {
        preparedMicrophone?.session.stopRunning()
        preparedMicrophone = nil
        if state == .idle { meter.publish(.silent, from: ObjectIdentifier(self)) }
    }

    /// `start`'s microphone: `adoptMicrophone(for:)`'s session and output,
    /// with the `.m4a` beside the movie.
    func microphoneCapture(for device: AVCaptureDevice, beside movie: URL) throws
        -> MicrophoneCapture
    {
        let url = RecordingFiles.microphoneURL(beside: movie)
        let adopted = try adoptMicrophone(for: device)
        return (adopted.session, adopted.output, url)
    }

    /// The capture session for `device`: the prepared session when its
    /// device is `device` and it is still running (a device that went away
    /// meanwhile stops its session), else a fresh one, which the caller will
    /// run. Either way the prepared slot is empty afterwards — adopted, or
    /// discarded because it was the wrong device. `start` (through
    /// `microphoneCapture`) and `startVoiceOver` both take theirs here.
    func adoptMicrophone(for device: AVCaptureDevice) throws
        -> (session: AVCaptureSession, output: AVCaptureAudioFileOutput)
    {
        if let prepared = preparedMicrophone, prepared.deviceID == device.uniqueID,
            prepared.session.isRunning
        {
            preparedMicrophone = nil
            return (prepared.session, prepared.output)
        }
        discardPreparedMicrophone()
        return try Self.microphoneSession(for: device)
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
    /// output's connection channels and publishes one reading: while
    /// RECORDING, the recording's output; while IDLE with a PREPARED session
    /// running, that session's output — the countdown's meter (#98 c: the
    /// connection was measured reporting levels on a running session
    /// before `startRecording`, 2026-09-30). A no-op — nothing published —
    /// idle with nothing prepared, arming, PAUSED, finishing (the pause
    /// published the silence), and once the LATEST segment's microphone has
    /// finished or failed (finding 3 published the silence then, and a dead
    /// connection must not light the bar again; a closed segment's state is
    /// not this segment's). A VOICE-OVER (`voiceSession`) is read the same
    /// way: its output while recording and its last segment has neither
    /// finished nor failed. One
    /// channel is reported on both sides, `LevelMeterSink`'s rule for a
    /// mono track (R0 q6c: the connection exposes `averagePowerLevel` and
    /// `peakHoldLevel` in dB on every poll, so there is no sample buffer and
    /// no queue in it).
    func publishMicrophoneLevel() {
        let connection: AVCaptureConnection?
        if state == .recording, let voice = voiceSession, let last = voice.segments.last,
            !last.finished, last.failure == nil
        {
            connection = voice.micOutput.connection(with: .audio)
        } else if state == .recording, let current = session, !current.latest.micFinished,
            current.latest.micFailure == nil, let output = current.micOutput
        {
            connection = output.connection(with: .audio)
        } else if state == .idle, let prepared = preparedMicrophone, prepared.session.isRunning {
            connection = prepared.output.connection(with: .audio)
        } else {
            connection = nil
        }
        guard let connection, let first = connection.audioChannels.first else { return }
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
