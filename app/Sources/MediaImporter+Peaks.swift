import AVFoundation
import CoreMedia
import Foundation

/// The await-free reader and publisher for the peaks pass. Asset properties
/// are loaded by `MediaImporter.peaks`, which owns the async boundary.
extension MediaImporter {
    static let peaksVersion = 1

    struct PeaksStamp: Codable, Equatable {
        let source: CacheStamp
        let version: Int

        init(_ source: CacheStamp) {
            self.source = source
            self.version = MediaImporter.peaksVersion
        }
    }

    static func readPeaksStamp(at url: URL) -> PeaksStamp? {
        guard let data = try? Data(contentsOf: url),
            let marker = try? JSONDecoder().decode(PeaksStamp.self, from: data),
            marker.version == peaksVersion
        else { return nil }
        return marker
    }

    static func peaksAreCurrent(for media: MediaSnapshot, stamp: CacheStamp?, in cacheDir: URL)
        -> Bool
    {
        guard let stamp,
            readPeaksStamp(at: peaksMarkerURL(for: media.id, in: cacheDir)) == PeaksStamp(stamp)
        else { return false }
        return loadPeaks(for: media.id, in: cacheDir) != nil
    }

    /// Intersect the selected track's target edits with its numeric extent.
    /// An explicitly empty edit is a gap. No segments means the ordinary
    /// unedited track, whose whole timeRange is required.
    static func expectedPeaksRanges(
        trackRange: CMTimeRange, segments: [AVAssetTrackSegment]
    ) -> [CMTimeRange]? {
        guard trackRange.isValid, trackRange.duration.isNumeric,
            CMTimeCompare(trackRange.duration, .zero) > 0 else { return nil }
        let targets = segments.isEmpty ? [trackRange] : segments.filter { !$0.isEmpty }
            .map { $0.timeMapping.target }
        var intervals: [CMTimeRange] = []
        for target in targets {
            guard target.isValid, target.duration.isNumeric else { return nil }
            let clipped = CMTimeRangeGetIntersection(trackRange, otherRange: target)
            if clipped.isValid, clipped.duration.isNumeric,
                CMTimeCompare(clipped.duration, .zero) > 0 { intervals.append(clipped) }
        }
        intervals.sort { CMTimeCompare($0.start, $1.start) < 0 }
        var merged: [CMTimeRange] = []
        for interval in intervals {
            if let last = merged.last,
                CMTimeCompare(interval.start, CMTimeRangeGetEnd(last)) <= 0 {
                merged[merged.count - 1] = CMTimeRangeFromTimeToTime(
                    start: last.start, end: CMTimeMaximum(CMTimeRangeGetEnd(last),
                                                          CMTimeRangeGetEnd(interval)))
            } else { merged.append(interval) }
        }
        return merged
    }

    static func writePeaks(
        for media: MediaSnapshot, asset: AVURLAsset, track: AVAssetTrack,
        expectedRanges: [CMTimeRange], stamp: CacheStamp?, into cacheDir: URL
    ) {
        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        guard reader.startReading() else { return }

        var peaks = PeakBuckets(duration: media.duration)
        while let sample = output.copyNextSampleBuffer() {
            if !peaks.add(sample) { break }
        }
        // A nil next buffer can mean either completion or decoder failure.
        // Cancelling first would erase that distinction.
        let status = reader.status
        reader.cancelReading()
        finishPeaks(peaks, status: status, expectedRanges: expectedRanges,
                    for: media, stamp: stamp, into: cacheDir)
    }

    /// The only publication path, shared by the actual reader and the probe.
    static func finishPeaks(
        _ peaks: PeakBuckets, status: AVAssetReader.Status,
        expectedRanges: [CMTimeRange], for media: MediaSnapshot,
        stamp: CacheStamp?, into cacheDir: URL
    ) {
        guard status == .completed, !peaks.failed, peaks.acceptedFrames > 0,
            peaks.covers(expectedRanges), let stamp else { return }
        let file = peaksURL(for: media.id, in: cacheDir)
        let marker = peaksMarkerURL(for: media.id, in: cacheDir)
        guard ensureDirectory(file.deletingLastPathComponent()) else { return }
        guard (try? peaks.data.write(to: file, options: .atomic)) != nil else { return }
        guard writeStamp(PeaksStamp(stamp), to: marker) else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        postCacheChange(media: media.id, kind: peaksKind)
    }
}
