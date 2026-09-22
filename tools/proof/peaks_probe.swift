import AVFoundation
import CoreMedia
import Foundation

var passed = 0
var failed = 0
func check(_ name: String, _ good: Bool, _ detail: String = "") {
    if good { passed += 1; print("  ok   \(name)") }
    else { failed += 1; print("  FAIL \(name) \(detail)") }
}
func media(_ url: URL, _ duration: Ticks, id: UInt32 = 1) -> MediaSnapshot {
    MediaSnapshot(id: id, path: url.path, kind: .audio, duration: duration,
                  hasVideo: false, hasAudio: true)
}
func directory(_ name: String) -> URL {
    let url = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.removeItem(at: url)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func awaitPeaks(_ m: MediaSnapshot, _ url: URL, _ stamp: MediaImporter.CacheStamp?,
                _ cache: URL) -> Bool {
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        await MediaImporter.peaks(for: m, url: url, stamp: stamp, into: cache)
        done.signal()
    }
    return done.wait(timeout: .now() + 60) == .success
}
func files(_ m: MediaSnapshot, _ cache: URL) -> (Bool, Bool) {
    (FileManager.default.fileExists(atPath: MediaImporter.peaksURL(for: m.id, in: cache).path),
     FileManager.default.fileExists(
        atPath: MediaImporter.peaksMarkerURL(for: m.id, in: cache).path))
}
func stamp(_ m: MediaSnapshot, _ url: URL) -> MediaImporter.CacheStamp? {
    MediaImporter.CacheStamp.stamp(for: m, url: url)
}
func inode(_ url: URL) -> UInt64? {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
}
func reader(_ url: URL) -> (AVAssetReader.Status, [CMSampleBuffer], CMTimeRange)? {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .audio).first,
          let r = try? AVAssetReader(asset: asset) else { return nil }
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false])
    guard r.canAdd(output) else { return nil }
    r.add(output)
    guard r.startReading() else { return nil }
    var samples: [CMSampleBuffer] = []
    while let next = output.copyNextSampleBuffer() { samples.append(next) }
    let status = r.status
    r.cancelReading()
    return (status, samples, track.timeRange)
}
func expectNoPublish(_ name: String, _ m: MediaSnapshot, _ cache: URL) {
    let state = files(m, cache)
    check(name, !state.0 && !state.1 && MediaImporter.loadPeaks(for: m.id, in: cache) == nil,
          "bin/marker: \(state)")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let oracle = (try? Data(contentsOf: root.appendingPathComponent("expected.json")))
    .flatMap { try? JSONDecoder().decode([String: [Float]].self, from: $0) } ?? [:]
let fullURL = root.appendingPathComponent("stereo48.wav")
let full = media(fullURL, 600_000)
let fullStamp = stamp(full, fullURL)
check("fixture has a source stamp", fullStamp != nil)
for name in ["mono44.wav", "mono48.wav", "stereo44.wav", "stereo48.wav",
             "silent48.wav", "tone.aac.m4a"] {
    let url = root.appendingPathComponent(name)
    let m = media(url, 600_000)
    let cache = directory(name)
    check("\(name) actual importer pass completes", awaitPeaks(m, url, stamp(m, url), cache))
    let values = MediaImporter.loadPeaks(for: m.id, in: cache)
    check("\(name) publishes marker and 100 buckets", values?.count == 100
          && files(m, cache) == (true, true))
    if let values, values.count == 100 {
        if name == "silent48.wav" {
            check("genuine all-zero PCM is usable", values.allSatisfy { $0 == 0 })
        } else if name == "tone.aac.m4a" {
            check("AAC decodes audible first and positive tail", values[10] > 0.15
                  && values[90] > 0.45, "\(values[10]), \(values[90])")
        } else {
            // Python independently authors these levels and counts frames.
            let first = 0.25 as Float
            let tail = name.hasPrefix("stereo") ? 0.875 as Float : 0.75 as Float
            check("\(name) first bucket matches authored frames",
                  abs(values[10] - first) < 0.0001, "\(values[10])")
            check("\(name) nonzero tail and channel max match authored frames",
                  abs(values[90] - tail) < 0.0001, "\(values[90])")
        }
        if name != "tone.aac.m4a", let expected = oracle[name], expected.count == 100 {
            let differences = zip(values, expected).enumerated().filter {
                abs($0.element.0 - $0.element.1) > 0.0001 }
            check("\(name) all buckets match independently counted fixture frames",
                  differences.isEmpty, "first mismatch \(differences.first?.offset ?? -1)")
        } else if name != "tone.aac.m4a" { check("\(name) independent bucket oracle exists", false) }
    }
}
let delayedURL = root.appendingPathComponent("delayed.mov")
let delayed = media(delayedURL, 900_000)
let delayedCache = directory("delayed")
let delaySegments = AVURLAsset(url: delayedURL).tracks(withMediaType: .audio).first?.segments
check("delayed fixture has an explicit empty edit then a nonempty target",
      delaySegments?.count == 2 && delaySegments?[0].isEmpty == true
      && delaySegments?[1].isEmpty == false)
check("delayed audio importer pass completes",
      awaitPeaks(delayed, delayedURL, stamp(delayed, delayedURL), delayedCache))
let delayedValues = MediaImporter.loadPeaks(for: delayed.id, in: delayedCache)
check("delayed audio certifies its selected track extent",
      delayedValues?.count == 150, "\(delayedValues?.count ?? -1)")
if let delayedValues, delayedValues.count == 150 {
    check("delayed audio keeps leading gap zero and later PCM audible",
          delayedValues[0] == 0 && delayedValues[40] > 0.15)
}
let delayedAACURL = root.appendingPathComponent("delayed.aac.m4a")
let delayedAAC = media(delayedAACURL, 900_000)
let delayedAACCache = directory("delayed-aac")
let aacSegments = AVURLAsset(url: delayedAACURL).tracks(withMediaType: .audio).first?.segments
check("delayed AAC has an empty edit and millisecond target timebase",
      aacSegments?.count == 2 && aacSegments?[0].isEmpty == true
      && aacSegments?[1].timeMapping.target.duration.timescale == 1000)
check("delayed AAC importer pass completes",
      awaitPeaks(delayedAAC, delayedAACURL, stamp(delayedAAC, delayedAACURL), delayedAACCache))
let delayedAACValues = MediaImporter.loadPeaks(for: delayedAAC.id, in: delayedAACCache)
check("one target-timebase unit accepts valid AAC's trimmed tail",
      delayedAACValues?.count == 150, "\(delayedAACValues?.count ?? -1)")
if let delayedAACValues, delayedAACValues.count == 150 {
    check("delayed AAC retains leading silence and audible tail",
          delayedAACValues[0] == 0 && delayedAACValues[90] > 0.45)
}
// Storage follows the record; coverage follows the track after a relink.
for (name, duration, count) in [("short-model", Ticks(300_000), 50),
                                ("long-model", Ticks(1_200_000), 200)] {
    let m = media(fullURL, duration)
    let cache = directory(name)
    check("\(name) pass completed", awaitPeaks(m, fullURL, stamp(m, fullURL), cache))
    let values = MediaImporter.loadPeaks(for: m.id, in: cache)
    check("\(name) uses record-sized storage", values?.count == count)
    if name == "long-model", let values, values.count == count {
        check("shorter sound leaves a genuine zero tail", values[90] > 0.7
              && values[150] == 0)
    }
}
// Legacy or damaged state is unavailable before the async rebuild begins.
let migration = directory("migration")
check("migration first pass completes", awaitPeaks(full, fullURL, fullStamp, migration))
let peakFile = MediaImporter.peaksURL(for: full.id, in: migration)
let markerFile = MediaImporter.peaksMarkerURL(for: full.id, in: migration)
let initialBytes = try? Data(contentsOf: peakFile)
let initialInode = inode(peakFile)
if let fullStamp {
    _ = MediaImporter.writeStamp(fullStamp, to: markerFile)
    check("legacy bare stamp is unavailable immediately",
          MediaImporter.loadPeaks(for: full.id, in: migration) == nil)
    check("legacy cache rebuild completes", awaitPeaks(full, fullURL, fullStamp, migration))
    check("legacy cache migrated to wrapper without changing payload",
          MediaImporter.readPeaksStamp(at: markerFile) == MediaImporter.PeaksStamp(fullStamp)
          && (try? Data(contentsOf: peakFile)) == initialBytes)
    let migratedInode = inode(peakFile)
    check("migrated cache reuse pass completes", awaitPeaks(full, fullURL, fullStamp, migration))
    let reusedInode = inode(peakFile)
    check("second pass reuses existing peaks inode", migratedInode != nil
          && migratedInode == reusedInode && initialInode != nil)
    let markerBytes = try? Data(contentsOf: markerFile)
    for label in ["future", "corrupt", "missing"] {
        if label == "missing" {
            try? FileManager.default.removeItem(at: markerFile)
        } else if label == "future", let markerBytes,
                  var object = (try? JSONSerialization.jsonObject(with: markerBytes))
                    as? [String: Any] {
            object["version"] = 2
            let future = try? JSONSerialization.data(withJSONObject: object)
            try? future?.write(to: markerFile)
            let sourceSize = ((object["source"] as? [String: Any])?["size"]
                as? NSNumber)?.int64Value
            check("future marker retains the real source stamp",
                  sourceSize == fullStamp.size)
        } else {
            try? Data("{".utf8).write(to: markerFile)
        }
        check("\(label) peaks marker is unavailable",
              MediaImporter.loadPeaks(for: full.id, in: migration) == nil)
    }
    if let markerBytes { try? markerBytes.write(to: markerFile) }
    try? Data([0, 0, 0]).write(to: peakFile)
    check("short non-frame-aligned payload is unavailable",
          MediaImporter.loadPeaks(for: full.id, in: migration) == nil)
    if let initialBytes { try? initialBytes.write(to: peakFile) }
    var negative = initialBytes ?? Data()
    if negative.count >= 4 { negative.replaceSubrange(0..<4, with: [0, 0, 128, 191]) }
    try? negative.write(to: peakFile)
    check("negative payload is unavailable", MediaImporter.loadPeaks(for: full.id, in: migration) == nil)
    var nan = initialBytes ?? Data()
    if nan.count >= 4 { nan.replaceSubrange(0..<4, with: [0, 0, 192, 127]) }
    try? nan.write(to: peakFile)
    check("nonfinite payload is unavailable", MediaImporter.loadPeaks(for: full.id, in: migration) == nil)
}
let nilActual = directory("nil-actual-pass")
check("nil-stamp actual importer pass completes", awaitPeaks(full, fullURL, nil, nilActual))
expectNoPublish("nil-stamp importer pass", full, nilActual)

if let decoded = reader(fullURL) {
    check("synthetic source reader completed with multiple real buffers",
          decoded.0 == .completed && decoded.1.count >= 3,
          "status \(decoded.0), buffers \(decoded.1.count)")
    let expected = [decoded.2]
    if let first = decoded.1.first {
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
            presentationTimeStamp: CMTime(value: 0, timescale: 1), decodeTimeStamp: .invalid)
        var coarse: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: first, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleBufferOut: &coarse)
        let coarseTime = coarse.map(CMSampleBufferGetPresentationTimeStamp)
        check("coarse timestamp fixture has real PCM and exact zero time",
              status == noErr && coarseTime?.value == 0 && coarseTime?.timescale == 1 &&
              CMSampleBufferGetNumSamples(first) < 19_200)
        var headOnly = MediaImporter.PeakBuckets(duration: full.duration)
        if let coarse { _ = headOnly.add(coarse) }
        let coarseTail = directory("coarse-zero-missing-tail")
        MediaImporter.finishPeaks(headOnly, status: .completed,
            expectedRanges: [CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))],
            for: full, stamp: fullStamp, into: coarseTail)
        expectNoPublish("exact zero timestamp cannot certify missing tail", full, coarseTail)
    } else { check("coarse timestamp fixture has a decoded buffer", false) }
    var covered = MediaImporter.PeakBuckets(duration: full.duration)
    for buffer in decoded.1 { _ = covered.add(buffer) }
    let coarseExact = directory("coarse-fractional-exact")
    let fractional = CMTimeRange(start: CMTime(value: 1, timescale: 10),
                                 duration: CMTime(value: 1, timescale: 10))
    MediaImporter.finishPeaks(covered, status: .completed, expectedRanges: [fractional],
                             for: full, stamp: fullStamp, into: coarseExact)
    check("exactly covered coarse fractional target publishes and reads back",
          files(full, coarseExact) == (true, true) &&
          MediaImporter.loadPeaks(for: full.id, in: coarseExact)?.count == 100)
    func synthetic(_ name: String, _ omit: Int?, _ ranges: [CMTimeRange]? = nil) {
        var buckets = MediaImporter.PeakBuckets(duration: full.duration)
        for (index, buffer) in decoded.1.enumerated() where index != omit {
            _ = buckets.add(buffer)
        }
        let cache = directory(name)
        MediaImporter.finishPeaks(buckets, status: .completed,
                                 expectedRanges: ranges ?? expected,
                                 for: full, stamp: fullStamp, into: cache)
        if ranges == nil { expectNoPublish(name + " completed but uncovered", full, cache) }
        else { check(name + " genuine edit gap publishes", MediaImporter.loadPeaks(
            for: full.id, in: cache) != nil) }
    }
    synthetic("missing-final", decoded.1.count - 1)
    synthetic("missing-middle", decoded.1.count / 2)
    // Only the omitted interval is an empty edit; neighbours remain required.
    if decoded.1.count >= 3 {
        let mid = decoded.1.count / 2
        let first = decoded.1[0]
        let last = decoded.1[decoded.1.count - 1]
        let firstStart = CMSampleBufferGetPresentationTimeStamp(first)
        let lastStart = CMSampleBufferGetPresentationTimeStamp(last)
        let firstEnd = CMTimeAdd(firstStart, CMSampleBufferGetDuration(first))
        let lastEnd = CMTimeAdd(lastStart, CMSampleBufferGetDuration(last))
        let left = CMTimeRangeFromTimeToTime(start: firstStart, end: firstEnd)
        let right = CMTimeRangeFromTimeToTime(start: lastStart, end: lastEnd)
        // Keep only endpoint buffers; the middle is an edited-out gap.
        var buckets = MediaImporter.PeakBuckets(duration: full.duration)
        _ = buckets.add(first); _ = buckets.add(last)
        let cache = directory("empty-edit")
        MediaImporter.finishPeaks(buckets, status: .completed,
                                 expectedRanges: [left, right], for: full,
                                 stamp: fullStamp, into: cache)
        check("explicit empty edit does not demand PCM", mid > 0 &&
              MediaImporter.loadPeaks(for: full.id, in: cache) != nil)
    }
    var all = MediaImporter.PeakBuckets(duration: full.duration)
    for buffer in decoded.1 { _ = all.add(buffer) }
    let incomplete = directory("failed-status")
    MediaImporter.finishPeaks(all, status: .failed, expectedRanges: expected,
                             for: full, stamp: fullStamp, into: incomplete)
    expectNoPublish("reader failure status", full, incomplete)
    let nilCache = directory("nil-stamp")
    MediaImporter.finishPeaks(all, status: .completed, expectedRanges: expected,
                             for: full, stamp: nil, into: nilCache)
    expectNoPublish("nil source stamp", full, nilCache)
    let unwritable = directory("marker-write-failure")
    let markerDirectory = MediaImporter.peaksMarkerURL(for: full.id, in: unwritable)
    try? FileManager.default.createDirectory(
        at: markerDirectory, withIntermediateDirectories: true)
    MediaImporter.finishPeaks(all, status: .completed, expectedRanges: expected,
                             for: full, stamp: fullStamp, into: unwritable)
    check("marker write failure removes just-written payload and stays unreadable",
          !FileManager.default.fileExists(
            atPath: MediaImporter.peaksURL(for: full.id, in: unwritable).path)
          && MediaImporter.loadPeaks(for: full.id, in: unwritable) == nil)

    var failedBuckets = MediaImporter.PeakBuckets(duration: full.duration)
    _ = failedBuckets.add(decoded.1[0])
    let damaged = decoded.1[1]
    let damagedBlock = CMSampleBufferGetDataBuffer(damaged)
    var nonfinite: Float = .nan
    let damagedStatus: OSStatus = damagedBlock.map { block in
        withUnsafePointer(to: &nonfinite) { value in
            CMBlockBufferReplaceDataBytes(with: value, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: 4)
        }
    } ?? -1
    check("nonfinite fixture altered a real PCM block", damagedStatus == noErr)
    check("nonfinite samples latch ingestion failure",
          !failedBuckets.add(damaged))
    for buffer in decoded.1.dropFirst(2) { _ = failedBuckets.add(buffer) }
    let failedCache = directory("invalid-buffer")
    MediaImporter.finishPeaks(failedBuckets, status: .completed,
                             expectedRanges: expected, for: full,
                             stamp: fullStamp, into: failedCache)
    expectNoPublish("latched ingestion failure", full, failedCache)

    // Declare full frame count over a block four bytes short; reject before copy.
    let ordinary = decoded.1[0]
    let declared = CMSampleBufferGetNumSamples(ordinary)
    let fullBytes = CMSampleBufferGetDataBuffer(ordinary).map(CMBlockBufferGetDataLength) ?? 0
    var shortBlock: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: fullBytes - 4,
        blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
        offsetToData: 0, dataLength: fullBytes - 4, flags: 0,
        blockBufferOut: &shortBlock)
    var shortSample: CMSampleBuffer?
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 48_000),
        presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(ordinary),
        decodeTimeStamp: .invalid)
    let sampleStatus: OSStatus = shortBlock.map { block in
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: CMSampleBufferGetFormatDescription(ordinary),
            sampleCount: declared, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0,
            sampleSizeArray: nil, sampleBufferOut: &shortSample)
    } ?? -1
    check("short PCM block fixture has declared frames", blockStatus == noErr
          && sampleStatus == noErr && shortSample != nil)
    if let shortSample {
        var shortBuckets = MediaImporter.PeakBuckets(duration: full.duration)
        check("short PCM block latches ingestion failure", !shortBuckets.add(shortSample))
        let shortCache = directory("short-block")
        MediaImporter.finishPeaks(shortBuckets, status: .completed,
                                 expectedRanges: expected, for: full,
                                 stamp: fullStamp, into: shortCache)
        expectNoPublish("short PCM block", full, shortCache)
    }
    if let highStream = reader(fullURL), let first = highStream.1.first,
        let block = CMSampleBufferGetDataBuffer(first) {
        var aboveFullScale: Float = 1.5
        let replaced = withUnsafePointer(to: &aboveFullScale) { value in
            CMBlockBufferReplaceDataBytes(with: value, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: 4)
        }
        check("above-full-scale fixture altered decoded PCM", replaced == noErr)
        var highBuckets = MediaImporter.PeakBuckets(duration: full.duration)
        for buffer in highStream.1 { _ = highBuckets.add(buffer) }
        let cache = directory("above-full-scale")
        MediaImporter.finishPeaks(highBuckets, status: highStream.0,
                                 expectedRanges: [highStream.2], for: full,
                                 stamp: fullStamp, into: cache)
        let values = MediaImporter.loadPeaks(for: full.id, in: cache)
        check("magnitudes above one survive publication and readback",
              values?.first == 1.5, "\(values?.first ?? -1)")
    } else {
        check("above-full-scale fixture can be decoded", false)
    }
}
let corruptURL = root.appendingPathComponent("corrupt.m4a")
let corrupt = media(corruptURL, 6_000_000)
let corruptRead = reader(corruptURL)
check("corrupt AAC fixture reports a reader failure or incomplete source coverage",
      corruptRead.map { $0.0 != .completed || $0.1.isEmpty } ?? false)
let corruptCache = directory("corrupt-aac")
check("corrupt AAC importer pass finishes", awaitPeaks(corrupt, corruptURL,
      stamp(corrupt, corruptURL), corruptCache))
expectNoPublish("corrupt AAC writer publishes nothing", corrupt, corruptCache)
let truncatedURL = root.appendingPathComponent("truncated.wav")
let truncated = media(truncatedURL, 600_000)
let truncatedRead = reader(truncatedURL)
check("truncated WAV has readable metadata or a failed reader", truncatedRead != nil)
let truncatedCache = directory("truncated-wav")
check("truncated WAV importer pass finishes", awaitPeaks(truncated, truncatedURL,
      stamp(truncated, truncatedURL), truncatedCache))
if let truncatedRead {
    let extent = CMTimeGetSeconds(truncatedRead.2.duration)
    // AVFoundation may rederive WAV extent from physical bytes. That is a
    // legitimate shorter selected track, not a truncated-decode failure.
    check("truncated WAV result follows actual selected-track extent",
          (extent <= 0.60001 && MediaImporter.loadPeaks(for: truncated.id, in: truncatedCache) != nil)
          || (extent > 0.60001 && MediaImporter.loadPeaks(for: truncated.id, in: truncatedCache) == nil),
          "track extent \(extent), reader \(truncatedRead.0)")
}
print("\n\(passed)/\(passed + failed) checks passed")
exit(failed == 0 ? 0 : 1)
