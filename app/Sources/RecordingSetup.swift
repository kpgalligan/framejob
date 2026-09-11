import AVFoundation
import AppKit
import ScreenCaptureKit

/// The half of screen recording a probe can call: values in, values out, no
/// framework object that needs a bundle (road map 3, R1a). What a recording
/// IS before it starts — the choice, where its files go, the two
/// ScreenCaptureKit configurations built from that choice, and the two
/// grants it stands on — so that `tools/proof/recording_probe.py` can read
/// every field back from a bare Mach-O that never starts a stream.
///
/// `ScreenRecorder.swift` (with `+Microphone.swift`, `+Finishing.swift` and
/// `+Content.swift`) is the other half: the class that owns the `SCStream`,
/// the `SCRecordingOutput` and, when a microphone is chosen, the
/// `AVCaptureSession` for the second file. The result types a recording
/// ends as — `StopReason`, `RecordingResult`, `RecorderError` — are at the
/// foot of this file, because they are values a probe can make.
///
/// Three R0 facts shape the configuration and are restated on the fields
/// they decide (`designs/reelcut-roadmap-3.md`, "R0 — the answers"):
///
/// - **The microphone is a second file** (q2). `captureMicrophone` on the
///   stream writes ONE stereo track that is the SUM of system and microphone
///   sound, which is decision 5's bad case — so `make` never sets it, and
///   `RecordingChoice.microphone` names an `AVCaptureDevice` for
///   `ScreenRecorder`'s capture session instead.
/// - **`.best` does not scale by itself** (q4). `captureResolution = .best`
///   at the display's point size writes a point-sized file; pixels come only
///   when `width`/`height` are asked for in pixels, so `make` multiplies the
///   point size by the display's backing scale under `.best` itself.
/// - **Show Clicks needs BGRA** (q6a). `SCStream.h` says `showMouseClicks`
///   "currently applies when pixelFormat is set to BGRA" and a fresh
///   configuration reads `420v`, so `make` sets `kCVPixelFormatType_32BGRA`
///   when clicks are on and leaves the default alone otherwise — measured, a
///   recording output over a BGRA stream starts and writes.

// MARK: - The choice

/// What is recorded. `.picked` is the panel's picker result, whose filter
/// is carried beside the choice (`ScreenRecorder.start` takes the filter as
/// its own argument), so the source enum never holds a framework object.
enum RecordingSource: Equatable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    case picked
}

/// `nominal` records the display's POINT size, `best` its pixel size
/// (`RecordingConfiguration.make` does the multiply — R0 q4).
enum RecordingResolution: String, CaseIterable {
    case nominal
    case best
}

/// Where the recording lands when it stops. `.document` carries the target's
/// `recipeKey` rather than an `ObjectIdentifier`: an identifier of a closed
/// document is reused by the next one at the same address
/// (`RelinkSheetController.swift` says so), while a `recipeKey` is never
/// minted twice, so `RecordingLanding.resolve`'s miss → `.newProject`
/// fallback is exact.
enum RecordingDestination: Equatable {
    case newProject
    case document(recipeKey: Int)
}

/// Every control of the recorder panel and every argument of
/// `record_screen`, as one value. `microphone` is an
/// `AVCaptureDevice.uniqueID`, nil for off; `rate` is 30 or 60.
struct RecordingChoice: Equatable {
    var source: RecordingSource = .display(CGMainDisplayID())
    var microphone: String? = nil
    var systemAudio: Bool = true
    var showClicks: Bool = false
    var rate: Int = 60
    var resolution: RecordingResolution = .nominal
    var destination: RecordingDestination = .newProject
    var folder: URL = RecordingFiles.folder()
}

// MARK: - Where the files go

/// Decision 2 (road map 3 §0): a recording is ORIGINAL footage and lives in
/// `~/Movies/Reelcut Recordings/`, named by date and time — never in the
/// package (an untitled document has none) and never in the temporary
/// directory (where a cache is regenerable and footage would be lost). The
/// folder is created on demand, and `-RCRecordingFolder` overrides it the
/// way `-RCFFmpegPath` overrides the binary (`FFmpegRewrap.locate`), so a
/// proof can record into `tools/proof/work/` and delete it.
enum RecordingFiles {
    /// The launch-argument override, read from `UserDefaults.standard` so it
    /// works from the argument domain (`-RCRecordingFolder ~/x` on the
    /// command line, or a pinned volatile domain in a probe).
    static let folderDefaultsKey = "RCRecordingFolder"

    /// The default folder's name under `~/Movies`.
    static let folderName = "Reelcut Recordings"

    /// The folder a recording goes into: the override, tilde-expanded, when
    /// one is set; `~/Movies/Reelcut Recordings/` otherwise. Nothing is
    /// created here — `create(_:)` is called at the moment a recording has
    /// something to put in it, `AppSupport`'s rule.
    static func folder() -> URL {
        if let override = UserDefaults.standard.string(forKey: folderDefaultsKey),
            !override.isEmpty
        {
            return URL(
                fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let movies =
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Movies", isDirectory: true)
        return movies.appendingPathComponent(folderName, isDirectory: true)
    }

    /// `Screen Recording 2026-09-10 at 14.03.22` — the Screenshot app's
    /// spelling, in the machine's own time zone. The formatter is pinned to
    /// `en_US_POSIX` so a locale with another digit set or a 12-hour clock
    /// cannot change the name's shape; the seconds make a name unique across
    /// the app's own recordings and `uniqueURL` handles the rest.
    static func stem(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "'Screen Recording' yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }

    /// `<stem>.<ext>` in `folder`, or `<stem> (2).<ext>`, `<stem> (3).<ext>`…
    /// while a file of that name exists — the Finder's own collision rule.
    static func uniqueURL(in folder: URL, stem: String, ext: String) -> URL {
        let manager = FileManager.default
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension(ext)
        var counter = 2
        while manager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) (\(counter))")
                .appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    /// The microphone's own file, beside the movie: the movie's stem plus
    /// ` (Microphone)`, as `.m4a` (R0 q6b: `AVCaptureAudioFileOutput` writes
    /// one mono 48 kHz AAC track there), made unique the same way.
    static func microphoneURL(beside movie: URL) -> URL {
        let stem = movie.deletingPathExtension().lastPathComponent + " (Microphone)"
        return uniqueURL(in: movie.deletingLastPathComponent(), stem: stem, ext: "m4a")
    }

    /// Makes the folder, intermediate directories included. A folder that
    /// already exists is not an error.
    static func create(_ folder: URL) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
    }
}

// MARK: - The configurations

/// The two ScreenCaptureKit configurations a choice becomes. PURE — every
/// field is set from the arguments and read back by the probe — which is
/// what lets the `excludesCurrentProcessAudio` mutant be caught at all: it
/// is invisible over MCP (nothing plays during a headless recording) and
/// this is the only row that sees it.
enum RecordingConfiguration {
    /// System audio is asked for at 48 kHz stereo, the rate the tap and
    /// `Loudness.swift` already assume of every file.
    static let sampleRate = 48_000
    static let channelCount = 2

    /// `displayPointSize` and `scale` come from the caller, and the caller is
    /// `ScreenRecorder.start`, which reads them off the FILTER — its
    /// `contentRect` (points) and `pointPixelScale` — the one geometry
    /// source that also covers a picker-made filter (`SCDisplay`'s
    /// `width`/`height` are POINTS, R0 q4, and a display filter reports the
    /// display's point size and backing scale, a window filter the window's
    /// frame). The probe passes the numbers directly. `outputURL` is
    /// assigned before the output configuration is returned, and must stay
    /// so: reading `outputURL` off a fresh `SCRecordingOutputConfiguration`
    /// TRAPS (it imports non-optional and is nil underneath until assigned —
    /// the SDK scout's finding, exit 133).
    static func make(
        _ choice: RecordingChoice, displayPointSize: CGSize, scale: CGFloat, outputURL: URL
    ) -> (stream: SCStreamConfiguration, output: SCRecordingOutputConfiguration) {
        let stream = SCStreamConfiguration()
        // R0 q4: pixels are asked for, `.best` does not scale by itself.
        let factor: CGFloat = choice.resolution == .best ? max(scale, 1) : 1
        stream.width = Int((displayPointSize.width * factor).rounded())
        stream.height = Int((displayPointSize.height * factor).rounded())
        stream.captureResolution = choice.resolution == .best ? .best : .nominal
        stream.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(choice.rate, 1)))
        stream.showsCursor = true
        stream.showMouseClicks = choice.showClicks
        // R0 q6a: the click circle draws only under BGRA; the default `420v`
        // is left alone when clicks are off, so an ordinary recording's
        // pixel path is byte for byte the spike's.
        if choice.showClicks { stream.pixelFormat = kCVPixelFormatType_32BGRA }
        stream.capturesAudio = choice.systemAudio
        stream.sampleRate = sampleRate
        stream.channelCount = channelCount
        // ALWAYS: the timeline can play while a recording runs and must not
        // be in it. `captureMicrophone` is deliberately never touched (R0
        // q2 — the microphone is a second file), so it keeps its default of
        // false, which the probe reads back on every row.
        stream.excludesCurrentProcessAudio = true

        let output = SCRecordingOutputConfiguration()
        output.outputURL = outputURL
        output.outputFileType = .mov
        // R0 q2: `availableVideoCodecTypes` is `[avc1, hvc1]` here and the
        // default is `avc1`; HEVC halves the file where the encoder offers it.
        output.videoCodecType =
            output.availableVideoCodecTypes.contains(.hevc) ? .hevc : .h264
        return (stream, output)
    }
}

// MARK: - The grants

/// Decision 4 (road map 3 §0): the PANEL asks for the grants, the tool never
/// does — `Transcriber.canAsk`'s rule for two grants. What lives here is the
/// synchronous READ of each and the sentence a refusal names the fix in;
/// `CGRequestScreenCaptureAccess()` and `AVCaptureDevice.requestAccess` are
/// called by the recorder panel alone, because a system prompt needs a
/// person in front of it.
///
/// **Both refusal sentences are COMPUTED, and end with `launchClause` when
/// it is non-empty** (R1 review, unjudged and upheld): R0 q1 measured that
/// a shell-launched Reelcut is attributed by TCC to the TERMINAL, so a
/// person who followed the pane sentence and granted Reelcut.app would have
/// granted the wrong application and be refused again with no way to tell
/// why. The pane sentence stays the PREFIX — `recording_proof.py` matches
/// on it — and the clause names the launching process's pid.
enum RecordingGrant {
    /// `CGPreflightScreenCaptureAccess()` — true when this PROCESS may
    /// capture. R0 q1: a shell-launched binary is attributed by TCC to the
    /// terminal, so from a proof this reads the terminal's grant, not the
    /// app's.
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// The pane sentence alone — the prefix of `screenRecordingRefusal`.
    static let screenRecordingPaneSentence =
        "Screen Recording is not granted to Reelcut. Turn it on in System Settings ▸ "
        + "Privacy & Security ▸ Screen & System Audio Recording, then relaunch."

    static var screenRecordingRefusal: String { screenRecordingPaneSentence + launchClause }

    /// Empty for an app launched by launchd (`open -a`, the Finder, the
    /// Dock — ppid 1, responsible for itself); otherwise the sentence that
    /// says whose grant this process is actually running under. `getppid()`
    /// is the cheapest true reading: R0 q1's `responsibility_get_pid_
    /// responsible_for_pid` is private API, and the parent is what TCC
    /// follows for a process launched from a shell.
    static var launchClause: String {
        let parent = getppid()
        guard parent != 1 else { return "" }
        return " This Reelcut was launched by another process (pid \(parent)), so the grant "
            + "that counts is that application's — the terminal's, for a shell launch; or "
            + "relaunch with open -a Reelcut.app."
    }

    /// `AVCaptureDevice.authorizationStatus(for: .audio)`. Read BEFORE any
    /// `AVCaptureDeviceInput` is made: that initializer auto-prompts on
    /// `.notDetermined`, which is exactly the prompt the tool may not put up.
    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// The status as the framework spells it, for a message a script can
    /// read — `Transcriber.name(of:)`'s shape.
    static func name(of status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    /// Names the status word and the one action that changes it: a
    /// `notDetermined` grant is asked for by pressing Record in the panel (the
    /// only place that may prompt), a denied or restricted one is turned on
    /// in System Settings. `launchClause` follows, on the same terms as the
    /// screen sentence's.
    static func microphoneRefusal(_ status: AVAuthorizationStatus) -> String {
        let head = "The microphone is not granted to Reelcut (status: \(name(of: status))). "
        switch status {
        case .notDetermined:
            return head + "Press Record in File ▸ New Recording… once to grant it." + launchClause
        default:
            return head + "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, "
                + "then relaunch." + launchClause
        }
    }
}

// MARK: - What a recording ends as

/// How the recording ended. `.stopped` is `ScreenRecorder.stop()`; the other
/// two are the stream delegate's `didStopWithError` codes −3817
/// (`.userStopped`, the system's own menu-bar indicator) and −3821
/// (`.systemStoppedStream`, a display that slept or went away).
enum StopReason: Equatable {
    case stopped
    case userStopped
    case systemStopped
}

/// The two files, probed, and how they line up — what `RecordingLanding`
/// turns into ops.
struct RecordingResult {
    /// The movie, probed through `MediaImporter.probe` (completion on main).
    let descriptor: MediaDescriptor
    /// The `.m4a`, probed, when a microphone was chosen AND its file landed;
    /// nil otherwise, and `micProblem` says which.
    let micDescriptor: MediaDescriptor?
    /// Screen did-start minus microphone did-start, in ticks. POSITIVE means
    /// the picture began AFTER the microphone, so the microphone clip starts
    /// that much earlier than the picture's (or has its in point trimmed by
    /// it). Measured per recording, never a constant (R0 q6b: +11 ms mean,
    /// 35 ms scatter with the session started first). 0 with no microphone.
    let micOffset: Ticks
    let choice: RecordingChoice
    /// The screen's did-start, wall clock.
    let startedAt: Date
    let stoppedBy: StopReason
    /// Non-nil when a microphone was chosen but its file did not land — it
    /// never started, the writer reported an error, the device went away,
    /// or the file would not probe (R1 review finding 0: a microphone
    /// problem does not fail a recording whose picture is on disk). The
    /// sentence names the file when one was left behind. `micDescriptor` is
    /// nil whenever this is set.
    let micProblem: String?

    init(
        descriptor: MediaDescriptor, micDescriptor: MediaDescriptor?, micOffset: Ticks,
        choice: RecordingChoice, startedAt: Date, stoppedBy: StopReason,
        micProblem: String? = nil
    ) {
        self.descriptor = descriptor
        self.micDescriptor = micDescriptor
        self.micOffset = micOffset
        self.choice = choice
        self.startedAt = startedAt
        self.stoppedBy = stoppedBy
        self.micProblem = micProblem
    }
}

/// `.busy` is `start()` while not idle, and nothing else answers it any
/// more: a `stop()` in any state joins the finishing already under way
/// (R1 review finding 1). `.startTimedOut` is the arm ceiling and
/// `.timedOut` the finish ceiling, two sentences because they name two
/// different waits (finding 5). `.filesKept` wraps a failure reached once
/// a file was on disk, so the panel's note and the tool's error carry the
/// path with no change on their side (finding 6).
indirect enum RecorderError: Error, LocalizedError {
    case busy
    case notRecording
    case startFailed(String)
    case finishFailed(String)
    case startTimedOut
    case timedOut
    case microphoneDevice(String)
    case filesKept(RecorderError, movie: String, microphone: String?)

    var errorDescription: String? {
        switch self {
        case .busy: return "A recording is already in progress."
        case .notRecording: return "No recording is in progress."
        case .startFailed(let why): return why
        case .finishFailed(let why): return why
        case .startTimedOut:
            return "The recording did not start within \(Int(ScreenRecorder.armCeiling)) s."
        case .timedOut:
            return "The recording did not finish writing within "
                + "\(Int(ScreenRecorder.finishCeiling)) s."
        case .microphoneDevice(let why): return why
        case .filesKept(let inner, let movie, let microphone):
            let clause = microphone.map { "; the microphone at \($0)" } ?? ""
            return (inner.errorDescription ?? "The recording failed.")
                + " The recording is at \(movie)\(clause)."
        }
    }
}
