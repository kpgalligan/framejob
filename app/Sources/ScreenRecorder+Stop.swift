import AVFoundation

/// `stop(completion:)` (camera-recording CR3-0): the one stop every door
/// sends — the panel's Stop, the menu bar's, `record_screen`'s — answered by
/// state, and forwarded to a voice-over's and a camera recording's own stops.
/// A pure move out of `ScreenRecorder.swift` at the 400-line cap, landed
/// alone before camera + screen grows the arming half there; nothing in it
/// changed. The state it reads and the finishing it begins
/// (`+Finishing.swift`) are internal already, so it costs no widening.
extension ScreenRecorder {
    // MARK: - Stop

    /// MAIN THREAD. `completion`, when given, on main with every file
    /// probed, or an error. Idle → `.notRecording`, synchronously; arming →
    /// held, finishing begins the moment the start lands; recording →
    /// finishing begins now; PAUSED → finishing begins now on the same
    /// path, with the segment's output already closed and the microphone
    /// already stopped, so only `stopCapture` remains; finishing → JOINED
    /// (finding 1): the completion is registered beside the others and
    /// never answered `.busy`, because a person's Stop a second after the
    /// menu bar's is a stop that must land. Every registered completion and
    /// the session's `onFinish` receive the ONE outcome at conclude. The
    /// wait for the writers is bounded at `finishCeiling`: past it the files
    /// are probed anyway (the writer may have finished without saying so),
    /// and an unfinished movie that will not probe is answered `.timedOut`.
    func stop(completion: ((Result<RecordingResult, Error>) -> Void)? = nil) {
        if voiceSession != nil { return stopVoiceOver(completion: completion) }
        if cameraSession != nil { return stopCamera(completion: completion) }
        switch state {
        case .idle:
            completion?(.failure(RecorderError.notRecording))
        case .arming:
            if let completion { stopCompletions.append(completion) }
            session?.stopAsked = true
            pendingStop = true
        case .recording, .paused:
            if let completion { stopCompletions.append(completion) }
            session?.stopAsked = true
            beginFinishing(.stopped)
        case .finishing:
            if let completion { stopCompletions.append(completion) }
        }
    }
}
