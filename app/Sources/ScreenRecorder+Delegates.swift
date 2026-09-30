import AVFoundation
import AppKit
import ScreenCaptureKit

/// The three delegates that tell the recorder what the frameworks did —
/// the foot of `ScreenRecorder+Finishing.swift`, cut here as a pure move
/// when R2's segments took that file over the 400-line cap, then taught to
/// find their SEGMENT. **Every delegate method hops to main first** and
/// then checks that the object calling belongs to the CURRENT session —
/// the screen's by the output's identity, the microphone's by the output's
/// identity AND the file URL it reports, since one
/// `AVCaptureAudioFileOutput` writes every segment's file — so a late
/// callback from a session that already failed or settled, or for a file
/// no segment asked for, changes nothing. A did-FINISH for a CLOSED segment
/// (the pause's, landing after the resume — R0 q7: 5–25 ms) is that
/// segment's flag and, while finishing, the wait's answer; what it is NOT
/// is the recording's end. A did-FAIL for the segment still RECORDING is (a
/// failed writer with a file open is `screenFailure`, the recording's); a
/// did-FAIL for a CLOSED segment is that segment's `outputFailure` and, like
/// its did-finish, the wait's answer — the walker leaves it out (#181). A
/// microphone did-finish carrying an error is that segment's `micFailure`
/// — and the session's `microphoneProblem` only MID-segment (#97): at a
/// boundary the machine asked for, it is that segment's alone.
/// `Segment.stoppedAt` is what says a did-finish was asked for.

// MARK: - The stream's delegate

extension ScreenRecorder: SCStreamDelegate {
    /// The system indicator's Stop, a display that slept, or a failure. The
    /// 15.2 `streamDidBecomeActive`/`Inactive` pair is optional and not
    /// implemented, so nothing here needs an `@available`.
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in self?.streamStopped(stream, error: error) }
    }

    private func streamStopped(_ stream: SCStream, error: any Error) {
        guard let current = session, current.stream === stream else { return }
        switch state {
        case .idle:
            return
        case .finishing:
            // An external stop whose did-finish landed FIRST (finding 7):
            // the output's finish began the path as `.stopped`, and the
            // reason arrives now. Adopted only when no `stop()` ended the
            // recording, so a person's own Stop keeps its name.
            if !current.stopAsked, current.stoppedBy == .stopped,
                let reason = Self.externalStop(error)
            {
                session?.stoppedBy = reason
            }
        case .arming:
            // The start's completion reports it (`captureStarted` reads it).
            session?.screenFailure = RecorderError.startFailed(Self.sentence(for: error))
        case .recording:
            // The indicator's, the system's, or a failure — and a failure
            // is the recording's, because a file is OPEN under it.
            if let reason = Self.externalStop(error) {
                beginFinishing(reason)
            } else {
                session?.screenFailure = RecorderError.finishFailed(Self.sentence(for: error))
                beginFinishing(.stopped)
            }
        case .paused:
            // The stream never stops for a pause (R0 q7), so a stop here is
            // the indicator's, the system's, or a failure — but NOTHING is
            // writing: the pause removed the output and its file is closed,
            // so a failure costs no footage and never fails the recording
            // (the R2 review: it did, with every file whole on disk). A
            // failure is read as the system's stop, which is what it is —
            // the stream is gone — and `settle` probes and lands.
            beginFinishing(Self.externalStop(error) ?? .systemStopped)
        }
    }
}

// MARK: - The recording output's delegate

extension ScreenRecorder: SCRecordingOutputDelegate {
    /// Stamped where it arrives (R0 q2: 86–107 ms BEFORE `startCapture`'s
    /// completion; q7: 8–10 ms after a resume's add), so the offset never
    /// includes the hop. Ignored once the segment is CLOSED (`stoppedAt`
    /// set): a pause inside those ~10 ms would otherwise take a start
    /// stamped after its own stop, and the span would run backwards — the
    /// fallback, the add's own call, is what `elapsed` and the result use.
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let at = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = self.session?.index(of: recordingOutput),
                let segment = self.session?.segments[index], segment.screenStartedAt == nil,
                segment.stoppedAt == nil
            else { return }
            self.session?.segments[index].screenStartedAt = at
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = self.session?.index(of: recordingOutput) else { return }
            self.session?.segments[index].screenFinished = true
            if self.session?.segments[index].stoppedAt != nil {
                // A CLOSED segment's writer gave up (#181): that segment's
                // alone — the walker leaves it out — never the recording's.
                if self.session?.segments[index].outputFailure == nil {
                    self.session?.segments[index].outputFailure =
                        .finishFailed("The recording failed: " + error.localizedDescription)
                }
                self.outputEnded(asked: true)
                return
            }
            if self.session?.screenFailure == nil {
                let sentence = "The recording failed: " + error.localizedDescription
                self.session?.screenFailure =
                    self.state == .arming ? .startFailed(sentence) : .finishFailed(sentence)
            }
            self.outputEnded(asked: false)
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let index = self.session?.index(of: recordingOutput) else { return }
            self.session?.segments[index].screenFinished = true
            self.outputEnded(asked: self.session?.segments[index].stoppedAt != nil)
        }
    }

    /// A did-finish the machine ASKED for — a pause's, or the stop's; the
    /// segment's `stoppedAt` says so — is the wait's answer while finishing
    /// and, before it, nothing more than the segment's own flag; so is a
    /// did-FAIL for such a CLOSED segment, which is its `outputFailure` and
    /// leaves it out (#181). One nobody asked for (the writer gave up) and a
    /// failure of the segment still RECORDING — `screenFailure`, which fails
    /// the recording (a movie that merely will not probe is left out, #97) —
    /// end the recording the way an external stop does. While arming, the
    /// start's completion reports it.
    private func outputEnded(asked: Bool) {
        switch state {
        case .recording, .paused:
            if !asked { beginFinishing(.stopped) }
        case .idle, .arming, .finishing:
            checkFinished()
        }
    }
}

// MARK: - The microphone file output's delegate

extension ScreenRecorder: AVCaptureFileOutputRecordingDelegate {
    /// Arrives on a private queue (R0 q6b), stamped here before the hop.
    func fileOutput(
        _ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        let at = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.session, current.micOutput === output,
                let index = current.index(ofMicrophoneFile: fileURL),
                current.segments[index].micStartedAt == nil
            else { return }
            self.session?.segments[index].micStartedAt = at
        }
    }

    /// The writer is done, well or badly. Badly while the picture still
    /// records (finding 3) — the device unplugged, the writer giving up —
    /// is a microphone PROBLEM and never the recording's end: the sentence
    /// is published at once for the panel's tick (once, kept: a later
    /// segment's failure is on its own segment), the meter goes silent when
    /// it is the LATEST segment's (a closed segment's late error has nothing
    /// to silence), and `settle` will carry it on that segment. Badly while
    /// arming is the same problem, seen earlier. Badly for a segment whose
    /// `stoppedAt` is set — a did-finish a pause or the stop ASKED for, e.g.
    /// −11805 for a writer stopped before its first sample — is that
    /// segment's `micFailure` and never `microphoneProblem` (#97): the other
    /// segments' voices are on disk, and the live note would say otherwise.
    func fileOutput(
        _ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection], error: (any Error)?
    ) {
        // A non-nil error can still mean a usable file: the key says so.
        let finishedWell =
            error == nil
            || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool)
                == true
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.session, current.micOutput === output,
                let index = current.index(ofMicrophoneFile: outputFileURL)
            else { return }
            self.session?.segments[index].micFinished = true
            if !finishedWell, current.segments[index].micFailure == nil, let error {
                let sentence = "The microphone recording failed: " + error.localizedDescription
                self.session?.segments[index].micFailure = sentence
                if self.microphoneProblem == nil, current.segments[index].stoppedAt == nil {
                    self.microphoneProblem = sentence
                }
                if index == current.lastIndex {
                    self.meter.publish(.silent, from: ObjectIdentifier(self))
                }
            }
            self.checkFinished()
        }
    }
}
