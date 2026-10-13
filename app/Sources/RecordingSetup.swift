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
/// `ScreenRecorder.swift` (with `+Pause.swift`, `+Microphone.swift`,
/// `+Finishing.swift`, `+Delegates.swift` and `+Content.swift`) is the other
/// half: the class that owns the `SCStream`, one `SCRecordingOutput` per
/// SEGMENT (R2: a pause removes one and a resume adds the next) and, when a
/// microphone is chosen, the `AVCaptureSession` for the second file. The
/// result types a recording ends as — `StopReason`, `RecordingSegment`,
/// `RecordingResult`, `RecorderError` — are `RecordingResult.swift`, moved
/// off the foot of this file at the 400-line cap; they are still values a
/// probe can make.
///
/// Three R0 facts shape the configuration and are restated on the fields
/// they decide (`archive/reelcut-roadmap-3.md`, "R0 — the answers"):
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
/// `.voiceOver` is the microphone alone, no picture (spec §11 recording, #99):
/// `ScreenRecorder.startVoiceOver` records it and `start` refuses it.
enum RecordingSource: Equatable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    case picked
    case voiceOver
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
    var includeFrameJobWindows: Bool = false
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
/// `~/Movies/Frame Job Recordings/`, named by date and time — never in the
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
    static let folderName = "Frame Job Recordings"

    /// The folder a recording goes into: the override, tilde-expanded, when
    /// one is set; `~/Movies/Frame Job Recordings/` otherwise. Nothing is
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

    /// `Voice-over 2026-10-02 at 09.15.04` — a voice-over's file, `stem(at:)`'s
    /// spelling and pinning with its own lead word.
    static func voiceOverStem(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "'Voice-over' yyyy-MM-dd 'at' HH.mm.ss"
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
/// does — the rule the speech grant's `canAsk` carried, for two grants.
/// What lives here is the READ of each grant, the STEP a press takes, the
/// pane URLs and the sentences — all pure: nothing here prompts or opens;
/// `CGRequestScreenCaptureAccess()`, `AVCaptureDevice.requestAccess` and
/// the pane's `NSWorkspace.open` are called by the recorder panel alone
/// (`RecorderPanelController+Grants.swift`), because a system prompt needs
/// a person in front of it. A press asks for Screen Recording ONCE and
/// opens the pane on every later press (spec §11 recording) — but only in
/// a launchd-owned launch: a shell-launched press always asks, because TCC
/// gives that prompt to the terminal (R0 q1). A denied or restricted
/// microphone opens its pane; `.notDetermined` asks.
///
/// **Both refusal sentences are COMPUTED, and end with `launchClause` when
/// it is non-empty** (R1 review, unjudged and upheld): R0 q1 measured that
/// a shell-launched Frame Job is attributed by TCC to the TERMINAL, so a
/// person who followed the pane sentence and granted Frame Job.app would have
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
        "Screen Recording is not granted to Frame Job. Turn it on in System Settings ▸ "
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
        return " This Frame Job was launched by another process (pid \(parent)), so the grant "
            + "that counts is that application's — the terminal's, for a shell launch; or "
            + "relaunch with open -a \"Frame Job\"."
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
        let head = "The microphone is not granted to Frame Job (status: \(name(of: status))). "
        switch status {
        case .notDetermined:
            return head + "Press Record in File ▸ New Recording… once to grant it." + launchClause
        default:
            return head + "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, "
                + "then relaunch." + launchClause
        }
    }

    // MARK: The step a press takes

    /// What a press of Record does about one grant: go on, put up the
    /// system prompt, or open System Settings at the grant's pane.
    enum Step: Equatable {
        case proceed
        case ask
        case openPane
    }

    /// True when launchd is the parent (`open -a`, the Finder, the Dock) —
    /// the reading `launchClause` makes, so the two cannot disagree.
    static var launchedByLaunchd: Bool { getppid() == 1 }

    /// Screen Recording: granted goes on; a shell launch always asks (its
    /// prompt is the terminal's, R0 q1, so `asked` means nothing there);
    /// a launchd-owned press that has asked before opens the pane; else ask.
    static func screenStep(granted: Bool, asked: Bool, launchedByLaunchd: Bool) -> Step {
        if granted { return .proceed }
        if !launchedByLaunchd { return .ask }
        if asked { return .openPane }
        return .ask
    }

    /// The microphone, when one is chosen: authorized goes on,
    /// `.notDetermined` asks, and denied, restricted or unknown opens the
    /// pane — the system never prompts twice for it.
    static func microphoneStep(_ status: AVAuthorizationStatus) -> Step {
        switch status {
        case .authorized: return .proceed
        case .notDetermined: return .ask
        case .denied, .restricted: return .openPane
        @unknown default: return .openPane
        }
    }

    /// System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording.
    static let screenRecordingPaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    /// System Settings ▸ Privacy & Security ▸ Microphone.
    static let microphonePaneURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")

    /// What a note adds once the pane has been opened.
    static let paneOpenedSentence = " System Settings is open at that pane."

    /// The screen note after the pane opened: the pane sentence stays the
    /// PREFIX, and `launchClause` stays last.
    static var screenRecordingOpenedNote: String {
        screenRecordingPaneSentence + paneOpenedSentence + launchClause
    }

    /// The microphone note after its pane opened: the refusal's head and
    /// fix, the opened sentence, then `launchClause`.
    static func microphoneOpenedNote(_ status: AVAuthorizationStatus) -> String {
        "The microphone is not granted to Frame Job (status: \(name(of: status))). "
            + "Turn it on in System Settings ▸ Privacy & Security ▸ Microphone, then relaunch."
            + paneOpenedSentence + launchClause
    }
}
