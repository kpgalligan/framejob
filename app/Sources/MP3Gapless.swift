import AVFoundation
import AudioToolbox

/// An MP3's own encoder delay, where Core Audio leaves it in (spec §11 SY-36,
/// SY-38).
///
/// **Why:** an MP3's first `encoderDelay` frames are the encoder's priming,
/// not the recording. Core Audio removes its decoder's own delay always, and
/// the encoder's only when it reports a packet table — from an iTunSMPB
/// comment, or from a LAME/Xing tag whose CRC it accepts. ffmpeg's muxer
/// writes the tag's CRC over the wrong bytes for every layout but MPEG-1
/// stereo, so Core Audio ignores such a tag and every AVFoundation reader
/// places the file's sound `encoderDelay` frames late (576 frames, +13.061 ms
/// at 44.1 kHz).
///
/// `leadingTrim` answers that delay, read from the file's own LAME/Xing tag
/// and applied as written, only when Core Audio has no packet table: a packet
/// table is never second-guessed. The 48 kHz copy (`AudioRateCopy`) and the
/// sync reader (`MediaImporter.writeSyncFeatures`) start their reads there.
///
/// The tag reader is pure (`firstFrameOffset`, `tag(frame:)`); `tag(at:)`
/// reads at most 10 + `frameReadLimit` bytes, and nothing is sized from the
/// ID3 header. Only a bare MPEG audio stream parses, so an MP3 track inside a
/// container (.mov, .mp4, .m4a) is never trimmed.
enum MP3Gapless {
    struct Tag: Equatable {
        let encoderDelay: Int
        let padding: Int
        let sampleRate: Int
    }

    /// At least the largest Layer III frame (1,441 bytes).
    static let frameReadLimit = 2_048

    private static let mpeg1Kbps = [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    private static let mpeg2Kbps = [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]

    /// Where the first frame starts: 0 when `head` does not start "ID3", else
    /// past the ID3v2 tag (10 + its synchsafe size, + 10 for a footer). Nil
    /// for an "ID3" head under 10 bytes or a size byte with bit 0x80 set.
    static func firstFrameOffset(head: Data) -> Int? {
        let bytes = [UInt8](head.prefix(10))
        guard bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 else {
            return 0
        }
        guard bytes.count >= 10 else { return nil }
        var size = 0
        for byte in bytes[6...9] {
            guard byte & 0x80 == 0 else { return nil }
            size = size << 7 | Int(byte)
        }
        return 10 + size + (bytes[5] & 0x10 != 0 ? 10 : 0)
    }

    /// The LAME extension of the Xing/Info header in `frame`, the first MPEG
    /// audio frame's bytes, else nil. Never reads past `frame.count`; the
    /// tag's CRC is not checked (Core Audio's acceptance is asked instead).
    static func tag(frame: Data) -> Tag? {
        let b = [UInt8](frame)
        guard b.count >= 4, b[0] == 0xFF, b[1] & 0xE0 == 0xE0 else { return nil }
        // 3: MPEG-1, 2: MPEG-2, 0: MPEG-2.5, 1: reserved.
        let version = (b[1] >> 3) & 3
        guard version != 1, (b[1] >> 1) & 3 == 1 else { return nil }
        let bitrateIndex = Int(b[2] >> 4)
        let rateIndex = Int((b[2] >> 2) & 3)
        guard bitrateIndex != 0, bitrateIndex != 15, rateIndex != 3 else { return nil }
        let mpeg1 = version == 3
        let kbps = (mpeg1 ? mpeg1Kbps : mpeg2Kbps)[bitrateIndex - 1]
        let rates = version == 3 ? [44_100, 48_000, 32_000]
            : version == 2 ? [22_050, 24_000, 16_000] : [11_025, 12_000, 8_000]
        let rate = rates[rateIndex]
        let length = (mpeg1 ? 144 : 72) * kbps * 1000 / rate + Int((b[2] >> 1) & 1)
        let mono = b[3] >> 6 == 3
        var at = 4 + (mpeg1 ? (mono ? 17 : 32) : (mono ? 9 : 17))
        guard at + 8 <= b.count else { return nil }
        let magic = String(decoding: b[at..<at + 4], as: UTF8.self)
        guard magic == "Xing" || magic == "Info" else { return nil }
        let flags = b[at + 4..<at + 8].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        at += 8
        if flags & 0x1 != 0 { at += 4 }
        if flags & 0x2 != 0 { at += 4 }
        if flags & 0x4 != 0 { at += 100 }
        if flags & 0x8 != 0 { at += 4 }
        guard at + 36 <= length, at + 36 <= b.count else { return nil }
        let encoder = String(decoding: b[at..<at + 4], as: UTF8.self)
        guard ["LAME", "Lavf", "Lavc"].contains(encoder) else { return nil }
        let packed = Int(b[at + 21]) << 16 | Int(b[at + 22]) << 8 | Int(b[at + 23])
        let delay = Int(packed >> 12)
        return Tag(encoderDelay: delay, padding: packed & 0xFFF, sampleRate: rate)
    }

    /// The tag of the file at `url`, read from its first frame; nil when the
    /// file has none, the frame would start at or past its end, or a read
    /// fails.
    static func tag(at url: URL) -> Tag? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: 0)
            let head = try handle.read(upToCount: 10) ?? Data()
            guard let offset = firstFrameOffset(head: head), UInt64(offset) < size else {
                return nil
            }
            try handle.seek(toOffset: UInt64(offset))
            return tag(frame: try handle.read(upToCount: frameReadLimit) ?? Data())
        } catch {
            return nil
        }
    }

    /// Whether Core Audio reports a packet table for the file (it then trims
    /// the encoder delay itself); nil when it cannot open the file.
    static func hasPacketTable(_ url: URL) -> Bool? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else {
            return nil
        }
        defer { AudioFileClose(file) }
        var info = AudioFilePacketTableInfo()
        var size = UInt32(MemoryLayout<AudioFilePacketTableInfo>.size)
        return AudioFileGetProperty(file, kAudioFilePropertyPacketTableInfo, &size, &info) == noErr
    }

    /// The source time a read of `track` (the file at `url`) starts at so its
    /// first frame is the recording's: the tag's encoder delay, for an MP3
    /// track whose tag matches its rate and for which Core Audio has no packet
    /// table; else zero.
    static func leadingTrim(of url: URL, track: AVAssetTrack) -> CMTime {
        guard let signature = CompositionBuilder.audioFormatSignature(of: track),
            signature.formatID == kAudioFormatMPEGLayer3,
            let tag = tag(at: url), tag.encoderDelay > 0,
            Double(tag.sampleRate) == signature.sampleRate
        else { return .zero }
        guard hasPacketTable(url) == false else { return .zero }
        return CMTime(value: Int64(tag.encoderDelay), timescale: CMTimeScale(tag.sampleRate))
    }
}
