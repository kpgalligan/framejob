import AVFoundation
import AppKit
import ScreenCaptureKit

/// The half of screen recording a probe can call: values in, values out, no
/// framework object that needs a bundle (road map 3, R1a). What a recording
/// IS before it starts — the choice, where its files go and the two
/// ScreenCaptureKit configurations built from that choice (the two grants
/// it stands on are `RecordingGrant.swift`'s) — so that
/// `tools/proof/recording_probe.py` can read every field back from a bare
/// Mach-O that never starts a stream.
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
/// they decide (`archive/roadmap-3.md`, "R0 — the answers"):
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
/// `.camera` is a camera alone, the device in `RecordingChoice.camera` (spec
/// §11 CAM-3): `ScreenRecorder.startCamera` records it and `start` refuses it,
/// while `start` records a camera beside a display, window or picked source (CAM-9).
enum RecordingSource: Equatable {
    case display(CGDirectDisplayID)
    case window(CGWindowID)
    case picked
    case voiceOver
    case camera
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
/// `AVCaptureDevice.uniqueID`, nil for off; `rate` is 30 or 60 (a camera
/// recording's is its format's, `CameraDevices.canvasRate`). `camera` is an
/// `AVCaptureDevice.uniqueID`, set with `source` `.camera`, or beside a
/// display, window or picked source (CAM-9), and `cameraFormat` its format
/// as `CameraDevices.spelled` writes it, nil for Best and set only with
/// `camera` (spec §11 CAM-6).
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
    var camera: String? = nil
    var cameraFormat: String? = nil
    /// Enhance Voice on the voice's clips after the landing; only with a microphone (AU-68, AU-69).
    var enhanceMicrophone: Bool = false
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
