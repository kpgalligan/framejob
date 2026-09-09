import AppKit
import Foundation

/// The opt-in ffmpeg step behind `MediaImporter`'s import funnel — spec §11's
/// named mitigation for choosing AVFoundation over a bundled ffmpeg.
///
/// **ffmpeg is not a dependency of this product and this file does not make it
/// one.** Nothing here links against ffmpeg, nothing here ships it, and every
/// entry point answers `nil` when the user has not installed one. The whole
/// feature is a courtesy: AVFoundation refuses Matroska and WebM outright
/// (`AVFoundationErrorDomain -11828 "Cannot Open"`, before it even looks at
/// the codecs inside), so an MKV that holds perfectly ordinary H.264 is
/// unopenable for a *container* reason. When the user already has an ffmpeg,
/// repackaging that MKV into a QuickTime file costs a stream copy — seconds,
/// no re-encode, no generation loss — and the clip imports. That is the whole
/// idea; the transcode path below exists only because VP9 and AV1 leave no
/// alternative.
///
/// Three rules shape everything here.
///
/// **Never a shell.** `Process` with `executableURL` and an argument array,
/// so a file called `; rm -rf ~` is an argument and not a command. Nothing in
/// this file ever builds a command *string*, and the tool's own location is
/// checked for being an executable file before it is run.
///
/// **Never silently expensive.** A stream copy is cheap and a transcode is
/// not, and the user is told which one they are about to pay for, with the
/// resolution, the running time and a size estimate, before anything starts
/// (`Plan.consentText`). The answer can be remembered — `RCFFmpegImport` in
/// `UserDefaults`, `ask` (the default), `always` or `never`.
///
/// **Never in the document package.** See `rewrapDirectory` for why the
/// converted file lands in Application Support and not in the `.reelcut`
/// bundle.
///
/// The orchestration is `assist(_:)`; `MediaImporter.probeAllowingRewrap` is
/// its only caller.
enum FFmpegRewrap {

    // MARK: - The preference

    /// What to do when AVFoundation refuses a file and an ffmpeg is present.
    /// Stored as a string so `-RCFFmpegImport always` on the command line —
    /// which is how a scripted or agent-driven run opts in — reads back
    /// through the argument domain like every other launch flag.
    enum Policy: String {
        case ask
        case always
        case never
    }

    static let policyDefaultsKey = "RCFFmpegImport"

    /// An explicit ffmpeg location, for a user whose install is somewhere
    /// `searchDirectories` does not look. Takes precedence over everything.
    static let toolDefaultsKey = "RCFFmpegPath"

    static var policy: Policy {
        let stored = UserDefaults.standard.string(forKey: policyDefaultsKey) ?? ""
        return Policy(rawValue: stored) ?? .ask
    }

    private static func remember(_ policy: Policy) {
        UserDefaults.standard.set(policy.rawValue, forKey: policyDefaultsKey)
    }

    /// Whether a modal question can actually be answered. An agent-driven app
    /// (`-AgentServerEnabled YES`) has nobody at the keyboard: an alert there
    /// would sit unanswered until `import_media`'s own 30-second ceiling
    /// expired, turning a clean "cannot read this file" into a timeout. So
    /// under the agent the stored policy decides on its own and `ask` means
    /// no — which is exactly today's behaviour, and a scripted run that wants
    /// the conversion says so with `-RCFFmpegImport always`.
    private static var canAsk: Bool {
        !UserDefaults.standard.bool(forKey: AgentServer.enabledDefaultsKey)
    }

    // MARK: - Errors

    /// Only ever thrown after the user (or the stored policy) said yes: a
    /// refusal or a missing ffmpeg is `nil` from `assist`, not an error, so
    /// the caller can report AVFoundation's own failure untouched.
    enum RewrapError: LocalizedError {
        case failed(URL, String)
        case timedOut(URL)

        var errorDescription: String? {
            switch self {
            case .failed(let url, let detail):
                let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return "Could not convert \(url.lastPathComponent) with ffmpeg."
                }
                return "Could not convert \(url.lastPathComponent) with ffmpeg: \(trimmed)"
            case .timedOut(let url):
                return "ffmpeg gave up converting \(url.lastPathComponent)."
            }
        }
    }

    /// How a `run` went wrong, named from the TOOL's point of view. Kept
    /// separate from `RewrapError` so the message the user reads names the
    /// file they dropped and not the binary that choked on it.
    private struct ToolFailure: Error {
        let detail: String
        let timedOut: Bool
    }

    // MARK: - Finding the user's ffmpeg

    /// A located install. `ffprobe` is required, not optional: without it the
    /// codecs inside the container are unknown, and the honest choice would
    /// then be to assume the worst and re-encode a file that only needed
    /// repackaging. Spending an hour of somebody's CPU on a guess is worse
    /// than the status quo, so a half install degrades to no install. Every
    /// ffmpeg distribution for macOS — Homebrew, MacPorts, the static
    /// builds — ships both binaries together.
    struct Tools {
        let ffmpeg: URL
        let ffprobe: URL
    }

    /// Where to look, in order, when `RCFFmpegPath` is unset. `PATH` comes
    /// first because a user who put a build ahead of Homebrew's meant it;
    /// the literal list follows because a GUI app launched from the Finder
    /// inherits `launchd`'s `PATH` (`/usr/bin:/bin:/usr/sbin:/sbin`), which
    /// contains no ffmpeg on any Mac. `/opt/homebrew` is spec §11's own
    /// example and is first among the literals on Apple silicon; the rest
    /// cover Intel Homebrew, MacPorts and a hand-installed binary.
    private static let searchDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin", "/bin",
    ]

    /// The located tools, or `nil` when the user has no usable ffmpeg — the
    /// answer that makes every caller fall back to exactly today's behaviour.
    ///
    /// Cached for the life of the process: this is a handful of `stat` calls
    /// and an import funnel would otherwise repeat them per file, but the
    /// point is really that the answer must not change halfway through a
    /// batch drop.
    static func tools() -> Tools? {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let resolved = resolvedTools { return resolved.value }
        let found = locate()
        resolvedTools = Box(found)
        return found
    }

    private static func locate() -> Tools? {
        guard let ffmpeg = locate("ffmpeg") else { return nil }
        // ffprobe sits next to ffmpeg in every install; prefer that sibling
        // over a `PATH` search so a user pointing `RCFFmpegPath` at one build
        // does not silently get another build's probe.
        let sibling = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
        if isExecutable(sibling) { return Tools(ffmpeg: ffmpeg, ffprobe: sibling) }
        guard let ffprobe = locate("ffprobe") else { return nil }
        return Tools(ffmpeg: ffmpeg, ffprobe: ffprobe)
    }

    private static func locate(_ name: String) -> URL? {
        if name == "ffmpeg", let override = UserDefaults.standard.string(forKey: toolDefaultsKey) {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return isExecutable(url) ? url : nil
        }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init) + searchDirectories
        for directory in directories where !directory.isEmpty {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
            if isExecutable(url) { return url }
        }
        return nil
    }

    private static func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else { return false }
        return manager.isExecutableFile(atPath: url.path)
    }

    // MARK: - Where the converted file goes

    /// `~/Library/Application Support/Reelcut/Rewrapped/`.
    ///
    /// **Why not inside the `.reelcut` package**, which is what spec §11's
    /// one-line sketch says. Two reasons, both discovered in the code:
    ///
    /// 1. There is frequently no package. Opening an MKV from the Finder
    ///    builds an UNTITLED document (`ProjectDocument.readMediaFile` nils
    ///    `fileURL` deliberately, and `intendedCacheDirectory` falls back to a
    ///    temporary directory precisely because of it). The import that needs
    ///    the conversion is the very import that has nowhere to put it, and a
    ///    file written to `NSTemporaryDirectory()` is orphaned by the first
    ///    Save As — which costs nothing for a regenerable thumbnail and loses
    ///    the user's footage here.
    /// 2. `ProjectDocument.fileWrapper(ofType:)` writes a package with
    ///    exactly two children, `project.json` and `cache`. Anything else put
    ///    in the bundle is dropped by the next save, autosave included. The
    ///    one surviving location, `cache/`, is documented as regenerable and
    ///    deletable (§5.6) — the last place to keep the only decodable copy of
    ///    somebody's source material.
    ///
    /// Application Support has neither problem: it exists before the document
    /// does, it survives every save and Save As, and a reopened project finds
    /// the file by the same absolute path it recorded. It is also shared, so
    /// importing the same MKV into a second project reuses the first
    /// conversion instead of paying for it twice. This keeps the §11 decision
    /// intact — media is *referenced*, not copied into the document — and the
    /// converted file behaves like any other referenced media: move it and the
    /// Media tab badges it missing and offers Relink…
    ///
    /// The two path components were spelled here, privately, until road map
    /// 2's phase 7 needed the same folder for `ExportPresets.json`. They are
    /// `AppSupport`'s now — one home for `~/Library/Application
    /// Support/Reelcut/`, which is where the argument above still lives; this
    /// only names the subfolder. The directory itself is still created by
    /// `convert`, at the moment there is something to put in it.
    static var rewrapDirectory: URL? {
        AppSupport.subdirectory("Rewrapped")
    }

    /// The converted file's name for `source`: the source's own stem, so the
    /// Media tab still reads recognisably, plus a digest of the source's
    /// path, size and modification date. The digest is what makes the result
    /// reusable AND self-invalidating — re-importing the same file finds the
    /// existing conversion, while re-encoding the source under the same name
    /// produces a different digest and a fresh conversion rather than a stale
    /// one.
    static func destination(for source: URL) -> URL? {
        guard let directory = rewrapDirectory, let digest = digest(of: source) else { return nil }
        return directory.appendingPathComponent("\(stem(of: source))-\(digest).mov")
    }

    /// A finished conversion of `source`, if one is already on disk. Checked
    /// before ffmpeg is even looked for, so a project whose media was
    /// converted last month still opens on a machine where ffmpeg has since
    /// been uninstalled.
    static func existingRewrap(of source: URL) -> URL? {
        guard let destination = destination(for: source),
            FileManager.default.fileExists(atPath: destination.path)
        else { return nil }
        return destination
    }

    /// Throws away a conversion that turned out to be unopenable, so the next
    /// import tries again instead of handing the same bad file back for ever
    /// — `existingRewrap` cannot tell a good `.mov` from a bad one, and only
    /// the caller that re-probed it knows.
    ///
    /// Refuses to delete anything that is not directly inside
    /// `rewrapDirectory`. This takes a URL and removes a file, which is
    /// exactly the shape of function that a bug elsewhere turns into a data
    /// loss, so the guard is not a formality.
    static func discard(_ url: URL) {
        guard let directory = rewrapDirectory,
            url.deletingLastPathComponent().standardizedFileURL.path
                == directory.standardizedFileURL.path
        else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// FNV-1a over path, byte size and modification second. Not a content
    /// hash: reading gigabytes to decide whether to convert gigabytes is the
    /// wrong trade, and the three attributes together already distinguish
    /// every file this will ever see. A collision would reuse the wrong
    /// conversion, which is why the *name* also carries the source's stem.
    private static func digest(of source: URL) -> String? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        guard let size = (attributes?[.size] as? NSNumber)?.int64Value else { return nil }
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(source.path)|\(size)|\(Int64(modified.rounded()))".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex
    }

    /// The source's base name reduced to characters that are unambiguous in a
    /// file name. This string is built from a file name the app did not
    /// choose, and it becomes a path component — so it is filtered rather
    /// than trusted, and bounded so a pathological name cannot push the
    /// result past the file system's limit.
    private static func stem(of source: URL) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let characters = source.deletingPathExtension().lastPathComponent.unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "_"
        }
        let text = String(characters.prefix(48))
        return text.isEmpty ? "media" : text
    }

    // MARK: - The plan

    /// What ffmpeg would be asked to do, and what it would cost. Built from
    /// ffprobe before anything is asked of the user, because "make the cost
    /// obvious before it starts" is the difference between a helpful step and
    /// an app that disappears for twenty minutes.
    struct Plan {
        let source: URL
        let destination: URL
        /// ffprobe's `codec_name` for the first stream of each type, or nil
        /// when the container has none.
        let videoCodec: String?
        let audioCodec: String?
        /// Whether that stream can be copied rather than re-encoded.
        let copiesVideo: Bool
        let copiesAudio: Bool
        let width: Int
        let height: Int
        let fps: Double
        let duration: Double
        let sourceBytes: Int64

        /// No re-encoding at all: the fast, lossless case, and the one this
        /// feature exists for.
        var isStreamCopy: Bool { copiesVideo && copiesAudio }

        /// Roughly what the result will weigh. A copy is the source's own
        /// size; an encode is estimated at 0.12 bits per pixel per frame plus
        /// the AAC bitrate, which is the right order of magnitude for the
        /// x264 CRF used below and is presented as "about", never as fact.
        var estimatedBytes: Int64 {
            if copiesVideo { return sourceBytes }
            let pixels = Double(max(1, width * height))
            let rate = fps > 0 ? fps : 30
            let bitsPerSecond = pixels * rate * 0.12 + (copiesAudio ? 0 : 256_000)
            let seconds = duration > 0 ? duration : 0
            return Int64((bitsPerSecond * seconds / 8).rounded())
        }

        /// The sentence the user reads before deciding. Names the codec that
        /// forced the choice, so "why is this one slow and that one instant"
        /// has an answer on screen.
        var consentText: String {
            let size = ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
            let tail =
                "\n\nThe original file is left exactly where it is; Reelcut imports the "
                + "converted copy from its Application Support folder."
            if isStreamCopy {
                return "\(source.lastPathComponent) is in a container AVFoundation will not open, "
                    + "but the \(codecList) inside it can be decoded as they are. ffmpeg can "
                    + "repackage it into a QuickTime movie by copying the streams — no "
                    + "re-encoding, no loss of quality, about \(size) and a few seconds."
                    + tail
            }
            if copiesVideo {
                // `copiesVideo` is also true when there is no picture at all
                // — an audio-only Matroska — and promising to copy a video
                // stream that does not exist would be a small lie.
                let sound = "\(audioCodec ?? "audio") soundtrack has to be re-encoded to AAC"
                let middle = videoCodec == nil
                    ? "The \(sound)"
                    : "The video can be copied as it is, but the \(sound)"
                return "\(source.lastPathComponent) is in a container AVFoundation will not open. "
                    + "\(middle). About \(size), and a few seconds."
                    + tail
            }
            return "\(source.lastPathComponent) is \(videoCodec ?? "in a format") this Mac cannot "
                + "decode, so repackaging is not enough — the whole file has to be re-encoded to "
                + "H.264. That is \(sizeLine) of video and takes at least as long as the clip "
                + "runs, usually longer. The result will be about \(size)."
                + tail
        }

        private var codecList: String {
            switch (videoCodec, audioCodec) {
            case (let video?, let audio?): return "\(video) video and \(audio) audio"
            case (let video?, nil): return "\(video) video"
            case (nil, let audio?): return "\(audio) audio"
            case (nil, nil): return "streams"
            }
        }

        private var sizeLine: String {
            let seconds = Int(duration.rounded())
            let clock = String(format: "%d:%02d", seconds / 60, seconds % 60)
            guard width > 0, height > 0 else { return clock }
            return "\(width)×\(height), \(clock)"
        }
    }

    /// Video codecs a QuickTime file can carry and this Mac can decode, so
    /// the stream is copied rather than re-encoded. Conservative on purpose:
    /// a codec wrongly listed here produces a `.mov` that AVFoundation opens
    /// and then cannot play, which is a far worse failure than a needless
    /// re-encode. VP8, VP9 and AV1 are deliberately absent — AVFoundation
    /// has no QuickTime mapping for any of them.
    private static let copyableVideo: Set<String> = [
        "h264", "hevc", "prores", "mjpeg", "mpeg4", "qtrle", "dvvideo",
    ]

    /// Audio codecs likewise. Opus, Vorbis, FLAC, AC-3 and MP3 are absent:
    /// re-encoding a soundtrack is seconds even for a long file, so the
    /// benefit of the doubt is not worth a silent track.
    private static let copyableAudio: Set<String> = [
        "aac", "alac", "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_f32le", "pcm_s16be",
        "pcm_s24be",
    ]

    /// Inspects `source` and decides copy versus encode per stream. `nil`
    /// when ffprobe cannot read the file or finds nothing to import — a
    /// container with no video and no audio is not something ffmpeg can
    /// rescue, and the caller's own "no video or audio the app can open"
    /// message is the better one.
    static func plan(for source: URL, with tools: Tools) -> Plan? {
        guard let destination = destination(for: source) else { return nil }
        let arguments = [
            "-v", "error", "-print_format", "json", "-show_streams", "-show_format",
            source.path,
        ]
        guard let result = try? run(tools.ffprobe, arguments, timeout: 20), result.status == 0,
            let root = (try? JSONSerialization.jsonObject(with: result.output)) as? [String: Any]
        else { return nil }

        let streams = (root["streams"] as? [[String: Any]]) ?? []
        let format = (root["format"] as? [String: Any]) ?? [:]
        let video = streams.first { $0["codec_type"] as? String == "video" }
        let audio = streams.first { $0["codec_type"] as? String == "audio" }
        // An attached cover image is a video stream with a still disposition;
        // importing it as the picture would be wrong, so it does not count.
        let isCover = ((video?["disposition"] as? [String: Any])?["attached_pic"] as? Int) == 1
        let videoCodec = isCover ? nil : video?["codec_name"] as? String
        let audioCodec = audio?["codec_name"] as? String
        guard videoCodec != nil || audioCodec != nil else { return nil }

        return Plan(
            source: source, destination: destination, videoCodec: videoCodec,
            audioCodec: audioCodec,
            copiesVideo: videoCodec.map { copyableVideo.contains($0) } ?? true,
            copiesAudio: audioCodec.map { copyableAudio.contains($0) } ?? true,
            width: isCover ? 0 : (video?["width"] as? Int) ?? 0,
            height: isCover ? 0 : (video?["height"] as? Int) ?? 0,
            fps: rate(video?["avg_frame_rate"] as? String),
            duration: Double(format["duration"] as? String ?? "") ?? 0,
            sourceBytes: Int64(format["size"] as? String ?? "") ?? 0)
    }

    /// ffprobe writes rates as `"30000/1001"`, and `"0/0"` when it has none.
    private static func rate(_ text: String?) -> Double {
        guard let parts = text?.split(separator: "/"), parts.count == 2,
            let num = Double(parts[0]), let den = Double(parts[1]), den > 0
        else { return 0 }
        return num / den
    }

    // MARK: - Consent

    /// Puts the cost in front of the user and returns their answer. Safe from
    /// any thread; on a background thread it hops to main and waits, which is
    /// sound because `assist` deliberately holds no lock across this call —
    /// see the comment there.
    static func consent(for plan: Plan) -> Bool {
        if Thread.isMainThread { return ask(plan) }
        var accepted = false
        DispatchQueue.main.sync { accepted = ask(plan) }
        return accepted
    }

    private static func ask(_ plan: Plan) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Reelcut cannot open “\(plan.source.lastPathComponent)”."
        alert.informativeText = plan.consentText
        alert.addButton(withTitle: plan.isStreamCopy ? "Repackage" : "Convert")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do this automatically from now on"
        let accepted = alert.runModal() == .alertFirstButtonReturn
        // "From now on" means the answer just given, not always yes: a user
        // who cancels with the box ticked is asking never to see this again.
        if alert.suppressionButton?.state == .on { remember(accepted ? .always : .never) }
        return accepted
    }

    // MARK: - Orchestration

    /// The whole opt-in step: a file AVFoundation refused goes in, a file it
    /// can open comes out.
    ///
    /// * `nil` — no help is available or none was wanted (no ffmpeg, the
    ///   policy says no, the user cancelled, ffprobe found nothing to
    ///   import). The caller reports AVFoundation's own failure, which is
    ///   exactly the behaviour of a machine with no ffmpeg on it.
    /// * a URL — a QuickTime file on disk, ready to probe.
    /// * a throw — the conversion was authorised and failed, which is worth
    ///   its own message rather than "could not read".
    ///
    /// Synchronous and unbounded in time by design: it is called from
    /// `MediaImporter`'s two synchronous faces, OUTSIDE the 30-second ceiling
    /// those put on the AVFoundation probe, because a transcode legitimately
    /// takes minutes and being killed at 30 seconds would be a bug rather
    /// than a safeguard.
    static func assist(_ source: URL) throws -> URL? {
        // Before ffmpeg is even looked for, and before the policy is even
        // read: a conversion already on disk is already paid for. The policy
        // governs whether ffmpeg RUNS, and reusing a finished file runs
        // nothing — a user who turned the feature off to stop being asked
        // should still get the copy they made last week.
        if let existing = existingRewrap(of: source) { return existing }

        // Read once, and read BEFORE ffprobe is spawned: a user who said
        // never, and an agent-driven app with nobody to ask, should cost
        // nothing beyond the `stat` above.
        let decided = policy
        if decided == .never || (decided == .ask && !canAsk) { return nil }
        guard let tools = tools(), let plan = plan(for: source, with: tools) else { return nil }
        if decided == .ask, !consent(for: plan) { return nil }

        // The lock starts HERE and not above. Consent can block on the main
        // thread, and the main thread can itself be inside this function
        // (`ProjectDocument.read(from:ofType:)` is allowed to run there) — so
        // a lock held across the alert would be a background thread waiting
        // for main while main waits for the lock. Two imports of the same
        // file may therefore both ask; the second finds the finished file on
        // the re-check below and never runs ffmpeg twice.
        conversionLock.lock()
        defer { conversionLock.unlock() }
        if FileManager.default.fileExists(atPath: plan.destination.path) {
            return plan.destination
        }
        return try convert(plan, with: tools)
    }

    // MARK: - Running ffmpeg

    private static func convert(_ plan: Plan, with tools: Tools) throws -> URL {
        let manager = FileManager.default
        guard (try? manager.createDirectory(
            at: plan.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)) != nil
        else {
            throw RewrapError.failed(plan.source, "the conversion folder could not be created")
        }

        // Written under a partial name and moved into place, so a crash, a
        // kill or a full disk leaves no truncated file that `existingRewrap`
        // would later hand out as finished.
        let partial = plan.destination.deletingPathExtension()
            .appendingPathExtension("partial.mov")
        try? manager.removeItem(at: partial)

        let result: ToolResult
        do {
            result = try run(
                tools.ffmpeg, arguments(for: plan, with: tools, writing: partial),
                timeout: timeout(for: plan))
        } catch let failure as ToolFailure {
            try? manager.removeItem(at: partial)
            throw failure.timedOut
                ? RewrapError.timedOut(plan.source)
                : RewrapError.failed(plan.source, failure.detail)
        }
        guard result.status == 0, manager.fileExists(atPath: partial.path) else {
            try? manager.removeItem(at: partial)
            throw RewrapError.failed(plan.source, lastLine(of: result.errorOutput))
        }
        do {
            try manager.moveItem(at: partial, to: plan.destination)
        } catch {
            try? manager.removeItem(at: partial)
            throw RewrapError.failed(plan.source, error.localizedDescription)
        }
        return plan.destination
    }

    /// The command. Only the first video and the first audio stream are
    /// carried over — that is all `MediaImporter.probeAsset` and
    /// `CompositionBuilder` ever read — and `-dn -sn` drops the data,
    /// subtitle and attachment streams a QuickTime file cannot hold anyway.
    /// The `?` on each `-map` makes it optional, so an audio-only Matroska
    /// and a silent WebM both work without a second command shape.
    private static func arguments(for plan: Plan, with tools: Tools, writing output: URL)
        -> [String] {
        var args = [
            // `-nostdin` matters: ffmpeg reads the terminal by default and a
            // GUI app gives it none, which is a hang rather than an error.
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-i", plan.source.path,
            "-map", "0:v:0?", "-map", "0:a:0?", "-dn", "-sn",
        ]
        if let codec = plan.videoCodec {
            if plan.copiesVideo {
                args += ["-c:v", "copy"]
                // HEVC in a QuickTime file must be tagged `hvc1`; ffmpeg's
                // default `hev1` tag produces a movie AVFoundation opens and
                // then shows as black.
                if codec == "hevc" { args += ["-tag:v", "hvc1"] }
            } else {
                args += encoderArguments(for: plan, with: tools)
            }
        }
        if plan.audioCodec != nil {
            args += plan.copiesAudio ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "256k"]
        }
        args += ["-movflags", "+faststart", "-f", "mov", output.path]
        return args
    }

    /// x264 at CRF 18 when the user's build has it — visually lossless, and
    /// the quality a source clip deserves before it is edited. VideoToolbox
    /// is the fallback for a build without libx264: hardware, always present
    /// on macOS, but rate-controlled by bitrate, so one is computed from the
    /// picture instead of hard-coded. `yuv420p` in both cases, because a
    /// 10-bit H.264 profile is not reliably decodable by AVFoundation.
    private static func encoderArguments(for plan: Plan, with tools: Tools) -> [String] {
        if hasLibX264(tools) {
            return ["-c:v", "libx264", "-crf", "18", "-preset", "veryfast", "-pix_fmt", "yuv420p"]
        }
        let pixels = Double(max(1, plan.width * plan.height))
        let rate = plan.fps > 0 ? plan.fps : 30
        let bits = min(60_000_000.0, max(2_000_000.0, pixels * rate * 0.12))
        return [
            "-c:v", "h264_videotoolbox", "-b:v", "\(Int(bits))", "-pix_fmt", "yuv420p",
        ]
    }

    /// Asked once per process, and only on the transcode path — a stream copy
    /// never needs an encoder, and spawning a process to find that out would
    /// tax the common case for nothing. Takes `tools` rather than calling
    /// `tools()`: this runs inside `convert`, and the two functions must not
    /// contend for the same lock (`stateLock` here, `conversionLock` there).
    private static func hasLibX264(_ tools: Tools) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let known = libX264 { return known }
        let result = try? run(
            tools.ffmpeg, ["-hide_banner", "-loglevel", "error", "-encoders"], timeout: 20)
        let text = String(decoding: result?.output ?? Data(), as: UTF8.self)
        let found = text.split(separator: "\n").contains { line in
            line.split(separator: " ").contains("libx264")
        }
        libX264 = found
        return found
    }

    /// How long ffmpeg gets. Generous, because the user consented to the
    /// cost and a slow disk is not a failure — but bounded, because a hung
    /// ffmpeg would otherwise hold the import path for ever. A copy is I/O
    /// and finishes in about the time it takes to read the file; an encode
    /// runs at some multiple of real time.
    private static func timeout(for plan: Plan) -> TimeInterval {
        let duration = max(0, plan.duration)
        let ceiling = plan.isStreamCopy ? max(300, duration * 2) : max(1800, duration * 30)
        return min(ceiling, 4 * 3600)
    }

    private static func lastLine(of data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return lines.last(where: { !$0.isEmpty }) ?? ""
    }

    // MARK: - Process plumbing

    private struct ToolResult {
        let status: Int32
        let output: Data
        let errorOutput: Data
    }

    /// Runs one tool with an argument ARRAY and no shell between here and it,
    /// which is the only reason a file named with a semicolon or a backtick
    /// is harmless.
    ///
    /// Both pipes are drained on their own queues while the process runs:
    /// reading them after `waitUntilExit` deadlocks the moment ffmpeg writes
    /// more than a pipe buffer's worth of diagnostics, which a long encode
    /// certainly does.
    private static func run(_ tool: URL, _ arguments: [String], timeout: TimeInterval) throws
        -> ToolResult {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // No terminal, and nothing for a tool to read: a child that blocks on
        // stdin would otherwise hang until the timeout.
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let collected = OutputBox()
        let drained = DispatchGroup()
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw ToolFailure(detail: error.localizedDescription, timedOut: false)
        }
        for (pipe, isError) in [(outPipe, false), (errPipe, true)] {
            drained.enter()
            DispatchQueue.global(qos: .utility).async {
                collected.append(pipe.fileHandleForReading.readDataToEndOfFile(), isError: isError)
                drained.leave()
            }
        }

        if exited.wait(timeout: .now() + timeout) != .success {
            process.terminate()
            if exited.wait(timeout: .now() + 10) != .success, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            _ = drained.wait(timeout: .now() + 10)
            throw ToolFailure(
                detail: "\(tool.lastPathComponent) did not finish in time", timedOut: true)
        }
        process.waitUntilExit()
        _ = drained.wait(timeout: .now() + 10)
        return ToolResult(
            status: process.terminationStatus, output: collected.output,
            errorOutput: collected.errorOutput)
    }

    /// Two background readers write into one of these; the caller reads it
    /// only after both have finished, and the lock covers the overlap.
    private final class OutputBox {
        private let boxLock = NSLock()
        private var out = Data()
        private var err = Data()

        func append(_ data: Data, isError: Bool) {
            boxLock.lock()
            defer { boxLock.unlock() }
            if isError { err.append(data) } else { out.append(data) }
        }

        var output: Data {
            boxLock.lock()
            defer { boxLock.unlock() }
            return out
        }

        var errorOutput: Data {
            boxLock.lock()
            defer { boxLock.unlock() }
            return err
        }
    }

    /// A once-computed answer that is allowed to be "no" — `Optional` alone
    /// could not tell "not looked yet" from "looked, found nothing".
    private final class Box {
        let value: Tools?
        init(_ value: Tools?) { self.value = value }
    }

    /// Guards the two once-computed answers below. Held only across a `stat`
    /// sweep or one short `-encoders` call, never across a conversion.
    private static let stateLock = NSLock()
    private static var resolvedTools: Box?
    private static var libX264: Bool?

    /// Serialises the conversions themselves, so two imports of one file
    /// cannot write the same destination at the same time. Deliberately a
    /// SECOND lock: `assist` holds this one for the length of an ffmpeg run,
    /// and `hasLibX264` runs inside that — one lock for both would deadlock
    /// on the first transcode.
    private static let conversionLock = NSLock()
}
