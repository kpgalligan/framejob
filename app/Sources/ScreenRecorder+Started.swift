import AppKit
import ScreenCaptureKit

/// How an arm ends: `captureStarted`, the stream's start answered to the
/// arming session, and `failStart`, a failed start torn down. A pure move
/// out of `ScreenRecorder.swift` under road map "creator-jobs" CU0a's toll
/// U2; `refuse`, the refusal before the arm, stays there, `private`.

extension ScreenRecorder {
    func captureStarted(_ stream: SCStream, error: (any Error)?, at: Date) {
        guard state == .arming, let current = session, current.stream === stream else { return }
        if let error { return failStart(RecorderError.startFailed(Self.sentence(for: error))) }
        // A stream stop or an output failure that arrived while arming. A
        // MICROPHONE failure that arrived meanwhile is not one: the picture
        // records and the result will say what became of the microphone.
        if let failure = current.screenFailure { return failStart(failure) }
        timer?.invalidate()
        timer = nil
        session?.captureStartedAt = at
        state = .recording
        let completion = startCompletion
        startCompletion = nil
        completion?(nil)
        // `.paused` too: the completion just ran, and may have paused.
        if pendingStop, state == .recording || state == .paused {
            pendingStop = false
            beginFinishing(.stopped)
        }
    }

    /// Tears a failed start down: the microphone session stopped, the stream
    /// asked to stop in case it did start, every completion answered — the
    /// start's with the error, every registered stop's with the same. A
    /// start that fails has ONE segment (no resume has happened). When its
    /// output had NOT begun writing the half-made microphone file is
    /// removed (it is ours and holds nothing); when it had (the arm timer
    /// past a stream that started), both files are footage: they stay, and
    /// the error names them (finding 6). A camera beside the screen goes too
    /// (`tearDownCameraBeside`, CAM-9 (8)).
    func failStart(_ error: RecorderError) {
        timer?.invalidate()
        timer = nil
        var delivered = error
        if let current = session {
            current.micOutput?.stopRecording()
            current.micSession?.stopRunning()
            current.stream.stopCapture { _ in }
            let first = current.segments[0]
            if first.screenStartedAt != nil {
                delivered = Self.namingFiles(error, current)
            } else if let micURL = first.micURL {
                try? FileManager.default.removeItem(at: micURL)
            }
            tearDownCameraBeside(current)
            // The cursor's poll and monitors, and its buffers (spec §11 CU-11).
            current.cursor?.stop()
            current.cursor?.discard()
        }
        session = nil
        state = .idle
        microphoneProblem = nil
        pendingStop = false
        discardPreparedMicrophone()
        let completion = startCompletion
        startCompletion = nil
        completion?(delivered)
        let stops = stopCompletions
        stopCompletions = []
        stops.forEach { $0(.failure(delivered)) }
    }
}
