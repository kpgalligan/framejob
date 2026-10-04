import Foundation

extension FFmpegRewrap {

    // MARK: - The plan

    /// ffprobe's `r_frame_rate`, as its two integers; both positive.
    struct FrameRate: Equatable {
        let num: Int
        let den: Int
    }

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
        /// The first video stream's `r_frame_rate`; nil when it is not two
        /// positive integers.
        let videoRate: FrameRate?

        /// The one plan written as MP4, snapped to its frame rate and checked
        /// before it is kept (spec §11 #227).
        var copiesVP9: Bool { copiesVideo && videoCodec == "vp9" }

        /// This plan with the video re-encoded: what a VP9 copy that failed
        /// falls back to. The sound is decided again, for a QuickTime file.
        func reencodingVideo() -> Plan {
            Plan(
                source: source, destination: destination, videoCodec: videoCodec,
                audioCodec: audioCodec, copiesVideo: false,
                copiesAudio: audioCodec.map { FFmpegRewrap.copyableAudio.contains($0) } ?? true,
                width: width, height: height, fps: fps, duration: duration,
                sourceBytes: sourceBytes, videoRate: videoRate)
        }

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
    /// re-encode. VP8 and AV1 are deliberately absent — AVFoundation has no
    /// QuickTime mapping for either. VP9 is not listed either: its copy is
    /// decided by `vp9CopyProfiles` and the stream's frame rate, written as
    /// MP4 and checked (spec §11 #227).
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

    /// The VP9 profiles whose stream is copied rather than re-encoded (spec
    /// §11 #227): the two this Mac's supplemental decoder plays (#216).
    static let vp9CopyProfiles: Set<Int> = [0, 2]

    /// Audio codecs copied beside a VP9 copy, whose file is MP4-format;
    /// everything else there is re-encoded to AAC.
    private static let mp4CopyableAudio: Set<String> = ["aac", "alac"]

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
        // A VP9 stream is copied only for a profile this Mac decodes and a
        // rate the copy can be snapped to; the copy itself is checked later
        // (`keepsFrameGrid`).
        let videoRate = isCover ? nil : frameRate(video?["r_frame_rate"] as? String)
        let copiesVP9 = videoCodec == "vp9" && videoRate != nil
            && (profile(video?["profile"]).map { vp9CopyProfiles.contains($0) } ?? false)
        let audioSet = copiesVP9 ? mp4CopyableAudio : copyableAudio

        return Plan(
            source: source, destination: destination, videoCodec: videoCodec,
            audioCodec: audioCodec,
            copiesVideo: videoCodec.map { copiesVP9 || copyableVideo.contains($0) } ?? true,
            copiesAudio: audioCodec.map { audioSet.contains($0) } ?? true,
            width: isCover ? 0 : (video?["width"] as? Int) ?? 0,
            height: isCover ? 0 : (video?["height"] as? Int) ?? 0,
            fps: rate(video?["avg_frame_rate"] as? String),
            duration: Double(format["duration"] as? String ?? "") ?? 0,
            sourceBytes: Int64(format["size"] as? String ?? "") ?? 0,
            videoRate: videoRate)
    }

    /// ffprobe's `profile`: a number, or a string whose last word is one
    /// (`"Profile 0"`); anything else is unknown.
    private static func profile(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        guard let text = value as? String, let word = text.split(separator: " ").last
        else { return nil }
        return Int(word)
    }

    /// `"30000/1001"` as its two integers; nil for `"0/0"` or anything that
    /// is not two positive integers.
    static func frameRate(_ text: String?) -> FrameRate? {
        guard let parts = text?.split(separator: "/"), parts.count == 2,
            let num = Int(parts[0]), let den = Int(parts[1]), num > 0, den > 0
        else { return nil }
        return FrameRate(num: num, den: den)
    }

    /// ffprobe writes rates as `"30000/1001"`, and `"0/0"` when it has none.
    private static func rate(_ text: String?) -> Double {
        guard let parts = text?.split(separator: "/"), parts.count == 2,
            let num = Double(parts[0]), let den = Double(parts[1]), den > 0
        else { return 0 }
        return num / den
    }

    /// The command. Only the first video and the first audio stream are
    /// carried over — that is all `MediaImporter.probeAsset` and
    /// `CompositionBuilder` ever read — and `-dn -sn` drops the data,
    /// subtitle and attachment streams a QuickTime file cannot hold anyway.
    /// The `?` on each `-map` makes it optional, so an audio-only Matroska
    /// and a silent WebM both work without a second command shape.
    static func arguments(for plan: Plan, with tools: Tools, writing output: URL)
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
                // A VP9 copy's packet times are snapped to its frame rate,
                // as a re-encode's are (spec §11 #227). One argument, no shell.
                if plan.copiesVP9, let rate = plan.videoRate {
                    args += ["-bsf:v", "setts=time_base=\(rate.den)/\(rate.num):prescale=1"]
                }
            } else {
                args += encoderArguments(for: plan, with: tools)
            }
        }
        if plan.audioCodec != nil {
            args += plan.copiesAudio ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "256k"]
        }
        // ffmpeg writes VP9 into no QuickTime file, so that one copy is
        // MP4-format under the same name.
        args += ["-movflags", "+faststart", "-f", plan.copiesVP9 ? "mp4" : "mov", output.path]
        return args
    }

    /// The frame check (spec §11 #227): whether every video packet of
    /// `file`, a VP9 copy, sits a whole number of frames after the first, and
    /// the first a whole number of frames from zero, at `plan.videoRate`.
    /// Read from the file with ffprobe, because ffmpeg's exit code does not
    /// say. Anything unreadable is false. Takes no lock: it runs inside
    /// `convert`.
    static func keepsFrameGrid(_ file: URL, of plan: Plan, with tools: Tools) -> Bool {
        guard let rate = plan.videoRate else { return false }
        let arguments = [
            "-v", "error", "-select_streams", "v:0", "-show_entries",
            "stream=time_base:packet=pts", "-of", "csv=p=0", file.path,
        ]
        guard let result = try? run(tools.ffprobe, arguments, timeout: 300), result.status == 0
        else { return false }
        var timescale: Int64?
        var times: [Int64] = []
        let text = String(decoding: result.output, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty { continue }
            if entry.hasPrefix("1/") {
                guard timescale == nil, let value = Int64(entry.dropFirst(2)), value > 0
                else { return false }
                timescale = value
            } else if let pts = Int64(entry) {
                times.append(pts)
            } else {
                return false
            }
        }
        guard let timescale, let first = times.first, first >= 0 else { return false }
        let (ticks, overflow) = timescale.multipliedReportingOverflow(by: Int64(rate.den))
        guard !overflow, ticks % Int64(rate.num) == 0 else { return false }
        let step = ticks / Int64(rate.num)
        guard step > 0, first % step == 0 else { return false }
        var expected = first
        for pts in times {
            guard pts == expected else { return false }
            expected += step
        }
        return true
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
}
