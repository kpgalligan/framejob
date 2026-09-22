import Accelerate
import CoreMedia
import Foundation

extension MediaImporter {
    /// One Float32 maximum magnitude per 10 ms of the media record. Coverage
    /// follows decoded presentation timestamps independently of that storage
    /// bound, so a shorter record cannot certify an unread track tail.
    struct PeakBuckets {
        private var buckets: [Float]
        private var coverage: [(start: Double, end: Double,
                                startUnit: Double, endUnit: Double)] = []
        private(set) var acceptedFrames = 0
        private(set) var failed = false

        init(duration: Ticks) {
            let count = max(1, Int((Double(duration) / Double(ReelTime.perSecond)
                * Double(MediaImporter.peakBucketsPerSecond)).rounded(.up)))
            buckets = [Float](repeating: 0, count: count)
        }

        var data: Data { buckets.withUnsafeBufferPointer { Data(buffer: $0) } }

        /// A malformed nonempty buffer latches failure. No bytes from it
        /// contribute either waveform values or claimed coverage.
        mutating func add(_ sample: CMSampleBuffer) -> Bool {
            guard !failed else { return false }
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames >= 0 else { failed = true; return false }
            if frames == 0 { return true }
            guard CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample),
                let format = CMSampleBufferGetFormatDescription(sample),
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                asbd.mFormatID == kAudioFormatLinearPCM,
                asbd.mSampleRate.isFinite, asbd.mSampleRate > 0,
                asbd.mBitsPerChannel == 32, asbd.mFramesPerPacket == 1,
                asbd.mChannelsPerFrame > 0,
                asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                asbd.mFormatFlags & kAudioFormatFlagIsPacked != 0,
                asbd.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                let block = CMSampleBufferGetDataBuffer(sample)
            else { failed = true; return false }
            let channels = Int(asbd.mChannelsPerFrame)
            let (samplesCount, samplesOverflow) = frames.multipliedReportingOverflow(by: channels)
            let (expectedBytes, bytesOverflow) = samplesCount.multipliedReportingOverflow(by: 4)
            guard !samplesOverflow, !bytesOverflow,
                asbd.mBytesPerFrame == channels * 4,
                asbd.mBytesPerPacket == asbd.mBytesPerFrame,
                CMBlockBufferGetDataLength(block) == expectedBytes,
                CMSampleBufferGetTotalSampleSize(sample) == expectedBytes,
                expectedBytes > 0
            else { failed = true; return false }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard time.isNumeric, time.timescale > 0 else { failed = true; return false }
            let start = CMTimeGetSeconds(time)
            let end = start + Double(frames) / asbd.mSampleRate
            guard start.isFinite, end.isFinite, end > start else {
                failed = true; return false
            }
            var samples = [Float](repeating: 0, count: samplesCount)
            let copied = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return -1 }
                return CMBlockBufferCopyDataBytes(
                    block, atOffset: 0, dataLength: expectedBytes, destination: base)
            }
            guard copied == noErr, samples.allSatisfy({ $0.isFinite }) else {
                failed = true; return false
            }

            // Timestamp placement preserves genuine leading and internal edit
            // gaps. Group adjacent frames in each bucket for a vDSP maximum;
            // values above full scale are deliberately retained.
            var frame = 0
            while frame < frames {
                let frameTime = start + Double(frame) / asbd.mSampleRate
                let bucketDouble = floor(frameTime * Double(MediaImporter.peakBucketsPerSecond))
                guard bucketDouble.isFinite, bucketDouble >= Double(Int.min),
                    bucketDouble < Double(Int.max) else { failed = true; return false }
                let bucket = Int(bucketDouble)
                var take = 1
                while frame + take < frames {
                    let nextTime = start + Double(frame + take) / asbd.mSampleRate
                    if floor(nextTime * Double(MediaImporter.peakBucketsPerSecond)) != bucketDouble {
                        break
                    }
                    take += 1
                }
                if bucket >= 0 && bucket < buckets.count {
                    var magnitude: Float = 0
                    samples.withUnsafeBufferPointer { buffer in
                        if let base = buffer.baseAddress {
                            vDSP_maxmgv(base + frame * channels, 1, &magnitude,
                                        vDSP_Length(take * channels))
                        }
                    }
                    buckets[bucket] = max(buckets[bucket], magnitude)
                }
                frame += take
            }
            acceptedFrames += frames
            // An exact integer timestamp such as 0/1 has no whole-second
            // uncertainty. Keep the decoded edge's own precision; an
            // unrelated buffer must not enlarge its allowance.
            let timestampUnit = time.value % Int64(time.timescale) == 0
                ? 0 : 1 / Double(time.timescale)
            let edgeUnit = max(1 / asbd.mSampleRate, timestampUnit)
            insertCoverage(start: start, end: end, unit: edgeUnit)
            return true
        }

        private mutating func insertCoverage(start: Double, end: Double, unit: Double) {
            var next = (start: start, end: end, startUnit: unit, endUnit: unit)
            var result: [(start: Double, end: Double,
                          startUnit: Double, endUnit: Double)] = []
            var inserted = false
            for old in coverage {
                if old.end < next.start - 1e-9 {
                    result.append(old)
                } else if next.end < old.start - 1e-9 {
                    if !inserted { result.append(next); inserted = true }
                    result.append(old)
                } else {
                    if old.start < next.start {
                        next.start = old.start
                        next.startUnit = old.startUnit
                    }
                    if old.end > next.end {
                        next.end = old.end
                        next.endUnit = old.endUnit
                    }
                }
            }
            if !inserted { result.append(next) }
            coverage = result
        }

        /// At each outer boundary permit at most its decoded PCM frame or
        /// fractional CMTime unit. Exact coverage needs no allowance. No
        /// allowance bridges an internal gap or reaches a whole bucket.
        func covers(_ expectedRanges: [CMTimeRange]) -> Bool {
            guard !failed, acceptedFrames > 0, !expectedRanges.isEmpty else { return false }
            for range in expectedRanges {
                guard range.isValid, range.start.isNumeric, range.duration.isNumeric,
                    CMTimeCompare(range.duration, .zero) > 0 else { return false }
                let start = CMTimeGetSeconds(range.start)
                let end = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
                guard start.isFinite, end.isFinite, end > start else { return false }
                // A fractional target such as AAC's 1250/1000 can differ
                // from decoded frames by one millisecond. Exact boundaries
                // and exact full coverage do not need metadata tolerance.
                func roundingUnit(_ time: CMTime) -> Double {
                    time.value % Int64(time.timescale) == 0
                        ? 0 : 1 / Double(time.timescale)
                }
                guard coverage.contains(where: {
                    let startShortfall = max(0, $0.start - start)
                    let endShortfall = max(0, end - $0.end)
                    if startShortfall == 0 && endShortfall == 0 { return true }
                    let bucket = 1 / Double(MediaImporter.peakBucketsPerSecond)
                    let startUnit = max($0.startUnit, roundingUnit(range.start))
                    let endUnit = max($0.endUnit,
                                      roundingUnit(CMTimeRangeGetEnd(range)))
                    return (startShortfall == 0 ||
                            startUnit < bucket && startShortfall <= startUnit)
                        && (endShortfall == 0 ||
                            endUnit < bucket && endShortfall <= endUnit)
                }) else { return false }
            }
            return true
        }
    }
}
