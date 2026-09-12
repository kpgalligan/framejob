import AVFoundation
import AppKit
import ScreenCaptureKit

/// The segment, and the two transitions that close one and open the next
/// (road map 3, R2a). ScreenCaptureKit has no pause — `SCStream` and
/// `SCRecordingOutput` carry none — and the header's one lever is
/// `removeRecordingOutput` ("Stops Recording if the stream is currently
/// recording") beside `addRecordingOutput` ("Starts Recording if stream is
/// already capturing"). R0 q7 measured that pair on a running stream: the
/// remove returns in under 0.1 ms and the removed output's did-finish
/// lands 5–25 ms later; the add returns in 0.2 ms and the new output's
/// did-start 8–10 ms later (67–78 ms for the first, after `startCapture`);
/// the stream never stops and keeps delivering 56–58 fps while paused, so
/// a pause costs what a recording costs and the system's own indicator
/// stays up. So a paused recording is a SEQUENCE of file pairs over ONE
/// stream (decision 6): `pause()` removes the segment's output and stops
/// the microphone's writer, `resume()` mints a segment named by ITS OWN
/// start time, adds a fresh output and restarts the writer to a new file
/// on the one running capture session. Each pair's screen-minus-microphone
/// offset is measured per segment (q7: −22 to +33 ms across resumes on one
/// host), which is why a `Segment` carries its own stamps and
/// `RecordingSegment` its own offset.
///
/// **A resume never waits for the paused segment's did-finish** (q7's
/// `immediate` row: the next output added the moment the previous is
/// removed is as clean as one added after a pause). That is why the
/// delegates (`ScreenRecorder+Delegates.swift`) find a segment by the
/// output's IDENTITY and by the FILE URL the microphone delegate reports,
/// never "the current one": the closed segment's did-finish can land after
/// the next has begun, and one `AVCaptureAudioFileOutput` writes every
/// segment's file.
///
/// **What a failed pair costs** is R1's posture, per segment: a movie that
/// will not probe fails the RECORDING (`settle`, naming every file); a
/// microphone file that will not is that segment's `micProblem`, and
/// `resume()` asks the writer to record the next segment regardless — each
/// is judged on its own file (q7: one poisoned writer failed every
/// restarted file, and another day's did not). Landing the readable
/// segments of a recording whose last one failed is the kinder rule and is
/// deliberately NOT built (road map 3, R2a records the alternative).
///
/// **Two limits the R2 review named and left.** A pause inside the ~10 ms
/// between a resume's add and its output's did-start closes a file the
/// writer may not have opened, and a movie that will not probe fails the
/// recording at the stop — R1's posture above, every file named — rather
/// than dropping the empty segment. And a microphone `startRecording`
/// followed by `stopRecording` before its first sample answers −11805 with
/// NO file (measured), which sets `microphoneProblem` for the SESSION —
/// the panel writes its note once — although every other segment's voice
/// is on disk and lands.
extension ScreenRecorder {
    /// What one file pair owns: the two URLs, the output writing the movie,
    /// and the stamps the offset and `elapsed` are read from. `addedAt` is
    /// the call that asked for the output — `start`'s, or the resume's
    /// `addRecordingOutput` — and the fallback for a did-start that never
    /// came; `stoppedAt` is the pause's, or the stop's, and non-nil means
    /// the segment's did-finish was ASKED for, which is how the output
    /// delegate tells a writer that gave up from one it told to stop.
    /// `RecordingSegment` (`RecordingResult.swift`) is what this becomes
    /// once probed.
    struct Segment {
        let movieURL: URL
        let micURL: URL?
        let output: SCRecordingOutput
        let addedAt: Date
        var micRecordingCalledAt: Date?
        var screenStartedAt: Date?
        var micStartedAt: Date?
        var stoppedAt: Date?
        var screenFinished = false
        var micFinished = false
        var micFailure: String?
    }

    var isPaused: Bool { state == .paused }

    /// MAIN THREAD, synchronous. `.recording` → `.paused`; `.paused` throws
    /// `.alreadyPaused` (`.notRecording`'s sentence would be false while
    /// `isRecording` is true); idle, arming and finishing throw
    /// `.notRecording`. Removes the segment's output from the stream (its
    /// did-finish lands on THAT segment, 5–25 ms later), stops the
    /// microphone's writer when there is one (likewise), stamps the
    /// segment's `stoppedAt`, counts the pause (`RecordingResult.pauses`),
    /// silences the meter — and that is all: the stream keeps capturing. A
    /// remove that throws is rethrown as `.finishFailed` — it is a file
    /// that could not be closed — and the recorder STAYS `.recording` with
    /// nothing changed, since the output is still attached and a Stop will
    /// close it.
    func pause() throws {
        guard state != .paused else { throw RecorderError.alreadyPaused }
        guard state == .recording, let current = session else {
            throw RecorderError.notRecording
        }
        do {
            try current.stream.removeRecordingOutput(current.latest.output)
        } catch {
            throw RecorderError.finishFailed(
                "The recording could not be paused: " + error.localizedDescription)
        }
        session?.segments[current.lastIndex].stoppedAt = Date()
        session?.pauses += 1
        // ALWAYS sent, `beginFinishing`'s rule: the SDK answers a request
        // with one did-finish even when nothing was written, and
        // `checkFinished` waits for it. A writer that already failed and
        // said so gets no second one, harmlessly: its did-finish with the
        // error set `micFinished`, and the wait reads the flag.
        current.micOutput?.stopRecording()
        state = .paused
        meter.publish(.silent, from: ObjectIdentifier(self))
    }

    /// MAIN THREAD, synchronous. `.paused` → `.recording`; anything else
    /// throws `.notPaused`. Mints the next segment: a movie named by THIS
    /// moment (decision 6 — `RecordingFiles.stem(at:)` at the resume,
    /// through `nextMovieURL`, which skips the names this session already
    /// holds), its microphone file beside it when the session
    /// has one, and a fresh `SCRecordingOutput` from the same
    /// `RecordingConfiguration.make` call the first was built from, added
    /// to the running stream. An add that throws is `.startFailed` and the
    /// recorder STAYS `.paused` — the stream still captures, and a Stop
    /// lands what was recorded — with no segment minted, so nothing waits
    /// for a did-finish that cannot come. Then the microphone writer is
    /// restarted to the new file, stamped where the call is made; the
    /// did-starts are stamped where they land (`+Delegates.swift`). Never
    /// waits for the paused segment's did-finish (the header). A
    /// microphone that failed on an earlier segment is asked again.
    func resume() throws {
        guard state == .paused, let current = session else { throw RecorderError.notPaused }
        let at = Date()
        let movieURL = Self.nextMovieURL(for: current, at: at)
        // Only the output half is taken: the stream runs on its own
        // configuration already, and the output's reads nothing but the
        // choice and the URL.
        let configs = RecordingConfiguration.make(
            current.choice, displayPointSize: current.displayPointSize, scale: current.scale,
            outputURL: movieURL)
        let output = SCRecordingOutput(configuration: configs.output, delegate: self)
        do {
            try current.stream.addRecordingOutput(output)
        } catch {
            throw RecorderError.startFailed(
                "The recording could not be resumed: " + error.localizedDescription)
        }
        var segment = Segment(
            movieURL: movieURL,
            micURL: current.micOutput == nil ? nil : RecordingFiles.microphoneURL(beside: movieURL),
            output: output, addedAt: at)
        if current.micOutput != nil { segment.micRecordingCalledAt = Date() }
        // Appended BEFORE the writer is asked, so the segment is there for
        // the callback that reports on it (a hop to main from main, but the
        // order is what a reader expects).
        session?.segments.append(segment)
        state = .recording
        if let micOutput = current.micOutput, let micURL = segment.micURL {
            micOutput.startRecording(to: micURL, outputFileType: .m4a, recordingDelegate: self)
        }
    }

    /// The resumed segment's movie: `RecordingFiles.uniqueURL`'s own rule —
    /// `<stem>.mov`, then `<stem> (2).mov`, `(3)`… — applied to the files
    /// on DISK and to the URLs this session already HOLDS. `uniqueURL` reads
    /// the disk alone, and a resumed segment's file does not exist until its
    /// output's did-start, ~10 ms after the add (R0 q7), so a resume → pause
    /// → resume inside that window, within one second, would mint the same
    /// name twice and the second output would write over the first's file.
    /// A candidate whose microphone file (`microphoneURL(beside:)`, the one
    /// spelling of that name) is held is skipped on the same terms. Spelled
    /// here rather than in `RecordingFiles` because the held set is the
    /// session's, and that file is the probe's pure half.
    private static func nextMovieURL(for session: Session, at date: Date) -> URL {
        let folder = session.choice.folder
        let stem = RecordingFiles.stem(at: date)
        var held = Set(session.segments.map(\.movieURL.path))
        held.formUnion(session.segments.compactMap { $0.micURL?.path })
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension("mov")
        var counter = 2
        while manager.fileExists(atPath: candidate.path) || held.contains(candidate.path)
            || held.contains(RecordingFiles.microphoneURL(beside: candidate).path)
        {
            candidate = folder.appendingPathComponent("\(stem) (\(counter))")
                .appendingPathExtension("mov")
            counter += 1
        }
        return candidate
    }
}

// MARK: - Finding a segment

extension ScreenRecorder.Session {
    var lastIndex: Int { segments.count - 1 }
    /// The segment recording now or, paused, the one just closed.
    var latest: ScreenRecorder.Segment { segments[lastIndex] }

    /// The segment `output` writes, by identity; nil for an output that
    /// belongs to no segment of this session.
    func index(of output: SCRecordingOutput) -> Int? {
        segments.firstIndex { $0.output === output }
    }

    /// The segment whose microphone file is `url` — compared by path, the
    /// one thing two `URL`s to a file agree on — nil for a file no segment
    /// asked for.
    func index(ofMicrophoneFile url: URL) -> Int? {
        segments.firstIndex { $0.micURL?.path == url.path }
    }

    /// Every segment's screen did-finish has landed and, with a microphone,
    /// every segment's mic did-finish: the finishing wait's question. The
    /// paused segments' may have been true for minutes.
    var allFinished: Bool {
        segments.allSatisfy { $0.screenFinished && (micOutput == nil || $0.micFinished) }
    }

    /// When segment `index`'s picture began: its did-start, else — for the
    /// first segment — `startCapture`'s completion, else the call that
    /// added its output (the resume; ~10 ms before the did-start, R0 q7).
    /// Nil only for the first segment while the arm has not landed.
    func screenStart(of index: Int) -> Date? {
        let segment = segments[index]
        if let at = segment.screenStartedAt { return at }
        return index == 0 ? captureStartedAt : segment.addedAt
    }
}
