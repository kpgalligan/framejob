import AVFoundation
import CoreMedia
import Foundation

/// The await-free half of the sync-features cache (road map "audio-sync-2",
/// AS-3; spec §11 SY-11, spec §5.6): `cache/sync/<id>.bin`, the MFCC frames
/// `SyncFeatures` makes of a file's sound, and its marker
/// `cache/sync/<id>.complete.json`. `MediaImporter.syncFeatures` owns the
/// async boundary (loading the track); everything here runs on
/// `copyNextSampleBuffer` and does not await, `MediaImporter+Speech.swift`'s
/// shape, and the marker is `PeaksStamp`'s (`MediaImporter+Peaks.swift`).
///
/// Nothing memoises features, so no pass here posts `.mediaCacheDidChange`:
/// `AudioSync.read` loads them from disk each time it runs.
extension MediaImporter {

    /// Bumped on ANY change to a `SyncFeatures` constant: an old `.bin` then
    /// reads as not written yet, never as another recipe's frames.
    static let syncFeaturesVersion = 1

    struct SyncFeaturesStamp: Codable, Equatable {
        let source: CacheStamp
        let version: Int

        init(_ source: CacheStamp) {
            self.source = source
            self.version = MediaImporter.syncFeaturesVersion
        }
    }

    /// `cache/sync/<media id>.bin` inside the document package.
    static func syncFeaturesURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("sync", isDirectory: true)
            .appendingPathComponent("\(media).bin")
    }

    /// `cache/sync/<media id>.complete.json`: a sidecar beside the `.bin`,
    /// `peaksMarkerURL`'s shape.
    static func syncFeaturesMarkerURL(for media: UInt32, in cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("sync", isDirectory: true)
            .appendingPathComponent("\(media).complete.json")
    }

    static func readSyncFeaturesStamp(at url: URL) -> SyncFeaturesStamp? {
        guard let data = try? Data(contentsOf: url),
            let marker = try? JSONDecoder().decode(SyncFeaturesStamp.self, from: data),
            marker.version == syncFeaturesVersion
        else { return nil }
        return marker
    }

    /// Whether the features for `media` are current: a stamp, a marker equal
    /// to `SyncFeaturesStamp(stamp)`, and a `.bin` that loads. A nil stamp
    /// never says yes.
    static func syncFeaturesAreCurrent(
        for media: MediaSnapshot, stamp: CacheStamp?, in cacheDir: URL
    ) -> Bool {
        guard let stamp,
            readSyncFeaturesStamp(at: syncFeaturesMarkerURL(for: media.id, in: cacheDir))
                == SyncFeaturesStamp(stamp)
        else { return false }
        return loadSyncFeatures(for: media.id, in: cacheDir) != nil
    }

    /// The cached frames, frame-major, or nil until a complete pass is
    /// certified: no marker or another version's, a `.bin` whose size is not
    /// a positive multiple of a frame's bytes, or a value that is not finite.
    /// Never silence.
    static func loadSyncFeatures(for media: UInt32, in cacheDir: URL) -> [Float]? {
        guard readSyncFeaturesStamp(at: syncFeaturesMarkerURL(for: media, in: cacheDir)) != nil
        else { return nil }
        let frameBytes = SyncFeatures.coefficients * MemoryLayout<Float>.size
        guard let data = try? Data(contentsOf: syncFeaturesURL(for: media, in: cacheDir)),
            data.count > 0, data.count % frameBytes == 0
        else { return nil }
        let values = data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
        guard values.allSatisfy({ $0.isFinite }) else { return nil }
        return values
    }

    /// The marker first, then the `.bin` (`clearPeaks`' order: a marker
    /// left alone certifies nothing without its `.bin`). Answers whether a
    /// `.bin` was removed.
    @discardableResult
    static func clearSyncFeatures(for media: UInt32, in cacheDir: URL) -> Bool {
        let manager = FileManager.default
        try? manager.removeItem(at: syncFeaturesMarkerURL(for: media, in: cacheDir))
        let file = syncFeaturesURL(for: media, in: cacheDir)
        guard manager.fileExists(atPath: file.path) else { return false }
        return (try? manager.removeItem(at: file)) != nil
    }

    /// Reads `track` as mono float at `SyncFeatures.sampleRate` (speech's
    /// output settings at that rate) through a `SyncFeatures.Extractor`, and
    /// publishes the frames only when the reader ended `.completed` — a
    /// decode that gave up part way is not a shorter file. The directory,
    /// the `.bin` and then the marker run inside one `CacheLedger.publish`,
    /// and a marker that will not write takes its `.bin` with it. A
    /// `canAdd`/`startReading` failure, no stamp, or no whole frame publishes
    /// nothing; the media then reads as still being analysed.
    static func writeSyncFeatures(
        for media: MediaSnapshot, asset: AVURLAsset, track: AVAssetTrack, stamp: CacheStamp?,
        into cacheDir: URL, pass: CachePass?
    ) {
        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Double(SyncFeatures.sampleRate),
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else { return }

        let extractor = SyncFeatures.Extractor()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount >= 4 else { continue }
            var samples = [Float](repeating: 0, count: byteCount / 4)
            let copied = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: byteCount, destination: base)
            }
            guard copied == noErr else { continue }
            samples.withUnsafeBufferPointer { extractor.feed($0) }
        }
        // Before the cancel, which would make every status `.cancelled`.
        let status = reader.status
        reader.cancelReading()
        let frames = extractor.finish()
        guard status == .completed, let stamp, !frames.isEmpty else { return }

        let file = syncFeaturesURL(for: media.id, in: cacheDir)
        let marker = syncFeaturesMarkerURL(for: media.id, in: cacheDir)
        let data = frames.withUnsafeBufferPointer { Data(buffer: $0) }
        CacheLedger.shared.publish(in: cacheDir, for: pass) {
            guard ensureDirectory(file.deletingLastPathComponent()) else { return }
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
            guard writeStamp(SyncFeaturesStamp(stamp), to: marker) else {
                try? FileManager.default.removeItem(at: file)
                return
            }
        }
    }
}
