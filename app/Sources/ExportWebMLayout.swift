import AVFoundation

/// `rc_webm_open`'s layout (spec §11 CX-15 (3)), the `Encodable` mirror of the core's
/// `WebmLayout`: what the `av1_webm` file is before its first packet. Built from the
/// settings (the size `ExportWriter.encodedSize` gives the encoder, the rate), the pump's
/// `av1C` record and sequence-header colour, its picture (HD-5's HDR10 blobs on PQ alone),
/// the Opus pre-skip when the composition has sound, and the chapters clamped and rebased
/// by `ExportChapter.partition` — the MP4 writer's own rule.
struct ExportWebMLayout: Encodable {
    struct Video: Encodable {
        let codecId = "V_AV1"
        let codecPrivateHex: String
        let width: Int
        let height: Int
        let fps: [Int]
        let colour: Colour
    }

    /// The sequence header's CICP, video range (Matroska's Range 1), 10 bits, and on PQ the
    /// two blobs `OutputTransform` writes everywhere else.
    struct Colour: Encodable {
        let matrix: Int
        let range = 1
        let transfer: Int
        let primaries: Int
        let bitsPerChannel = 10
        let mdcvHex: String?
        let clliHex: String?
    }

    struct Audio: Encodable {
        let codecId = "A_OPUS"
        let channels = 2
        let sampleRate = 48_000
        let preSkip: Int
    }

    struct Chapter: Encodable {
        let startNs: Int64
        let endNs: Int64
        let name: String
    }

    let durationNs: Int64
    let video: Video
    /// nil for a composition with no sound: the silent movie (CX-15 (2)).
    let audio: Audio?
    let chapters: [Chapter]

    init(
        settings: ExportSettings, range: CMTimeRange, config: ReelAV1.Config,
        picture: ExportAV1Picture, preSkip: Int?, chapters: [ExportChapter]
    ) {
        let frame = ExportWriter.encodedSize(settings)
        let hdr10 = picture.carriesHDR10
        durationNs = ExportWebMPacketSink.nanoseconds(range.duration)
        video = Video(
            codecPrivateHex: Self.hex(config.record), width: frame.width, height: frame.height,
            fps: [settings.fps.num, settings.fps.den],
            colour: Colour(
                matrix: config.color.matrix, transfer: config.color.transfer,
                primaries: config.color.primaries,
                mdcvHex: hdr10 ? Self.hex(OutputTransform.masteringDisplay) : nil,
                clliHex: hdr10 ? Self.hex(OutputTransform.contentLightLevel) : nil))
        audio = preSkip.map { Audio(preSkip: $0) }
        self.chapters = ExportChapter.partition(chapters, in: range).map {
            Chapter(
                startNs: ExportWebMPacketSink.nanoseconds($0.range.start),
                endNs: ExportWebMPacketSink.nanoseconds($0.range.end), name: $0.name)
        }
    }

    /// The layout as the core reads it: snake_case keys, an absent optional left out.
    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let text = String(data: try encoder.encode(self), encoding: .utf8) else {
            throw Exporter.ExportError.failed("The WebM layout could not be written.")
        }
        return text
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
