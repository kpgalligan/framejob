import AVFoundation
import CoreMedia
import Foundation

/// The await-free half of the loudness pass (spec §11 AU-10): the cache's
/// files and marker, its load, clear and head check, and the reader and
/// publisher `MediaImporter.loudness` runs on the cache lane — the peaks
/// pass's shape (`MediaImporter+Peaks.swift`) for `cache/loudness/<id>.bin`.
/// `async`/`await` is confined to `MediaImporter.swift`.
extension MediaImporter {
    /// The cache's format. A marker of another version reads as absent and the
    /// cache is made again (no migration, SY-34's posture). 2 since each
    /// record gained the high band (spec §11 AU-63).
    static let loudnessVersion = 2

    /// The versioned wrapper of the file's `CacheStamp`, with what sizes a
    /// record: `blocksPerSecond` (100) and `oversample` (4) are in it so a
    /// build that changes either rebuilds.
    struct LoudnessStamp: Codable, Equatable {
        let source: CacheStamp
        let version: Int
        let channels: Int
        let sampleRate: Int
        let blocksPerSecond: Int
        let oversample: Int
    }

    /// `cache/loudness/<media id>.bin`.
    static func loudnessURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("loudness", isDirectory: true)
            .appendingPathComponent("\(media).bin")
    }

    /// `cache/loudness/<media id>.complete.json`, `peaksMarkerURL`'s shape.
    static func loudnessMarkerURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("loudness", isDirectory: true)
            .appendingPathComponent("\(media).complete.json")
    }

    static func readLoudnessStamp(at url: URL) -> LoudnessStamp? {
        guard let data = try? Data(contentsOf: url),
            let marker = try? JSONDecoder().decode(LoudnessStamp.self, from: data),
            marker.version == loudnessVersion,
            marker.blocksPerSecond == peakBucketsPerSecond,
            marker.oversample == 4,
            (1...2).contains(marker.channels)
        else { return nil }
        return marker
    }

    /// The cache, or nil until a current marker certifies a `.bin` of
    /// exactly `⌈duration·100⌉` records of width 3 (mono) or 8 (stereo)
    /// whose every value is finite, with z, tp and h ≥ 0 (`zLR` and `hLR`
    /// may be negative).
    static func loadLoudness(for media: UInt32, in cacheDir: URL) -> MediaLoudness? {
        guard let marker = readLoudnessStamp(at: loudnessMarkerURL(for: media, in: cacheDir))
        else { return nil }
        let duration = Double(marker.source.duration) / Double(ReelTime.perSecond)
        let count = (duration * Double(peakBucketsPerSecond)).rounded(.up)
        guard count.isFinite, count >= 0, count < Double(Int.max / 32) else { return nil }
        let records = max(1, Int(count))
        let width = marker.channels == 1 ? 3 : 8
        let url = loudnessURL(for: media, in: cacheDir)
        guard let data = try? Data(contentsOf: url),
            data.count == records * width * MemoryLayout<Float>.size
        else { return nil }
        let values = data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
        for (index, value) in values.enumerated() {
            guard value.isFinite else { return nil }
            // The cross terms, stereo's `zLR` and `hLR`, alone may be negative.
            if value < 0, !(width == 8 && (index % 8 == 2 || index % 8 == 7)) { return nil }
        }
        return MediaLoudness(channels: marker.channels, count: records, records: values)
    }

    /// `clearPeaks`' posture: the marker first, then the `.bin`. Returns
    /// whether a `.bin` was removed, the fact a post must follow.
    @discardableResult
    static func clearLoudness(for media: UInt32, in cacheDir: URL) -> Bool {
        let manager = FileManager.default
        try? manager.removeItem(at: loudnessMarkerURL(for: media, in: cacheDir))
        let file = loudnessURL(for: media, in: cacheDir)
        guard manager.fileExists(atPath: file.path) else { return false }
        return (try? manager.removeItem(at: file)) != nil
    }

    static func loudnessIsCurrent(for media: MediaSnapshot, stamp: CacheStamp?, in cacheDir: URL)
        -> Bool
    {
        guard let stamp,
            readLoudnessStamp(at: loudnessMarkerURL(for: media.id, in: cacheDir))?.source == stamp
        else { return false }
        return loadLoudness(for: media.id, in: cacheDir) != nil
    }

    /// `peaks`' head: a media with no audio withdraws a `.bin` still on disk
    /// (while current) and needs no pass; a current cache needs none; a stale
    /// one is withdrawn (while current, posted at once) and needs one.
    static func loudnessPassNeeded(
        for media: MediaSnapshot, stamp: CacheStamp?, in cacheDir: URL, pass: CachePass?
    ) -> Bool {
        guard media.hasAudio, media.duration > 0 else {
            if pass?.isCurrent() ?? true, clearLoudness(for: media.id, in: cacheDir) {
                postCacheChange(media: media.id, kind: loudnessKind)
            }
            return false
        }
        if loudnessIsCurrent(for: media, stamp: stamp, in: cacheDir) { return false }
        if pass?.isCurrent() ?? true, clearLoudness(for: media.id, in: cacheDir) {
            postCacheChange(media: media.id, kind: loudnessKind)
        }
        return true
    }

    /// Decodes the track at its own rate in 32-bit float, `writePeaks`'
    /// reader, through `LoudnessBlocks`. A file whose first buffer has more
    /// than two channels is read again from the start asking for two
    /// (`AVNumberOfChannelsKey`), at the same rate; that downmix is not
    /// measured against the export's (spec §11 AU-10).
    @discardableResult
    static func writeLoudness(
        for media: MediaSnapshot, asset: AVURLAsset, track: AVAssetTrack,
        expectedRanges: [CMTimeRange], stamp: CacheStamp?, into cacheDir: URL,
        pass: CachePass? = nil
    ) -> Bool {
        let lead = MP3Gapless.leadingTrim(of: asset.url, track: track)
        var downmixRate: Double?
        while true {
            guard let reader = try? AVAssetReader(asset: asset) else { return false }
            var settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            if let downmixRate {
                settings[AVNumberOfChannelsKey] = 2
                settings[AVSampleRateKey] = downmixRate
            }
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return false }
            reader.add(output)
            guard reader.startReading() else { return false }

            var blocks = LoudnessBlocks(duration: media.duration, lead: lead)
            var first = true
            var again = false
            while let sample = output.copyNextSampleBuffer() {
                if first, downmixRate == nil,
                    let format = CMSampleBufferGetFormatDescription(sample),
                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                    asbd.mChannelsPerFrame > 2, asbd.mSampleRate > 0 {
                    downmixRate = asbd.mSampleRate
                    again = true
                    break
                }
                first = false
                if !blocks.add(sample) { break }
            }
            // A nil next buffer can mean either completion or decoder failure.
            // Cancelling first would erase that distinction.
            let status = reader.status
            reader.cancelReading()
            if again { continue }
            return finishLoudness(
                blocks, status: status, expectedRanges: peaksRanges(expectedRanges, less: lead),
                for: media, stamp: stamp, into: cacheDir, pass: pass)
        }
    }

    /// The only publication path, shared by the reader and the probe: the
    /// directory, the `.bin`, its marker (or the `.bin`'s removal) and the
    /// post inside one `CacheLedger.publish`, `finishPeaks`' shape. Answers
    /// whether it published.
    @discardableResult
    static func finishLoudness(
        _ blocks: LoudnessBlocks, status: AVAssetReader.Status,
        expectedRanges: [CMTimeRange], for media: MediaSnapshot,
        stamp: CacheStamp?, into cacheDir: URL, pass: CachePass? = nil
    ) -> Bool {
        guard status == .completed, !blocks.failed, blocks.acceptedFrames > 0,
            blocks.covers(expectedRanges), let stamp, let channels = blocks.channels,
            let rate = blocks.sampleRate
        else { return false }
        let marker = LoudnessStamp(
            source: stamp, version: loudnessVersion, channels: channels,
            sampleRate: Int(rate.rounded()), blocksPerSecond: peakBucketsPerSecond,
            oversample: 4)
        let file = loudnessURL(for: media.id, in: cacheDir)
        let markerURL = loudnessMarkerURL(for: media.id, in: cacheDir)
        var published = false
        CacheLedger.shared.publish(in: cacheDir, for: pass) {
            guard ensureDirectory(file.deletingLastPathComponent()) else { return }
            guard (try? blocks.data.write(to: file, options: .atomic)) != nil else { return }
            guard writeStamp(marker, to: markerURL) else {
                try? FileManager.default.removeItem(at: file)
                return
            }
            postCacheChange(media: media.id, kind: loudnessKind)
            published = true
        }
        return published
    }
}
