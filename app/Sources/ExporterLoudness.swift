import AVFoundation

/// Pass one of an export: read the composed mix and MEASURE it (`Loudness.swift`).
///
/// This is `Exporter`'s own "Measuring the mix" section, in a file of its own
/// because `Exporter.swift` went past app/CLAUDE.md's ~600-line cap when phase
/// 5 put a second pass in it. It is a MOVE and nothing else — the same methods,
/// the same order, the same bodies — so `Exporter.swift`'s five internal members
/// (`lock`, `measuring`, `scratchStorage`, `scratchCapacity`, and the
/// `isCancelled` / `setMeasureProgress` accessors over that lock) are internal
/// only to be reachable from here. Stored properties cannot live in an
/// extension, which is the whole reason the split is where it is.
///
/// **What it buys.** Every export that carries sound gets a measured
/// "Peak −1.0 dBTP · −14.0 LUFS" on its final line, and an export that asked to
/// be normalised gets the gain that lands it on its target. The pass is a
/// reader with no writer, no video output and no encoder — audio decode through
/// the plan's own mix, and nothing else — so it costs a few per cent of a movie
/// export and roughly doubles an audio-only one, which is also the case where
/// the number matters most.
///
/// **It builds its OWN composition.** An `AVAudioMix` copy shares the
/// `MTAudioProcessingTap` objects its input parameters hold, and a tap carries
/// per-instance state (the compressor's envelope, the noise reducer's delay
/// line), so two readers over one mix would interleave into one tap's. Running
/// them strictly in sequence would *probably* survive on `AudioTapContext`'s
/// start-of-stream reset — but not for a range shorter than its 0.1 s seek
/// tolerance, and a second build costs one more pass of opening asset tracks on
/// a queue that exists for exactly that and removes the argument entirely. It is
/// the same movie by construction: the same plan JSON, the same media, the same
/// recipe slot. Its `videoComposition` is never read. `Exporter.export` is where
/// that second build happens; everything below is what it is handed.
///
/// **Nothing here can fail an export.** Every refusal is a nil, which means "no
/// loudness figure" and never "no file": the write pass that follows is the one
/// that decides whether there is one.
extension Exporter {

    // MARK: - Measuring the mix

    /// What the measurement READS: `ExportAudioGain.floatMixSettings`, the
    /// one float dictionary, and the same one the write pass reads whenever a
    /// gain applies (spec §11 #86). So a normalised export's gain is applied
    /// to exactly the signal measured here. An export with no gain is written
    /// from `ExportWriter.decodedAudioSettings`, the 16-bit decode it always
    /// had, so its bytes do not change.
    ///
    /// **Why float.** Int16 SATURATES. A mix hotter than full scale — which
    /// is exactly the material loudness normalisation exists for — would be
    /// measured clipped, and its true peak would be pinned at 0 dBTP by the
    /// decode rather than by the signal. Read as float, the overshoot is
    /// measured whole, the true-peak ceiling turns it down, and the gained
    /// file holds it unclipped. Only a hot mix written with NO gain is
    /// clipped, by its 16-bit decode, and `ExportLoudness.mixClipped` says so.
    ///
    /// **Why the rate and the channel count are the writer's.** BS.1770-4
    /// sums weighted channel powers and left and right both carry 1.0, so
    /// the same signal measured as one channel and written as two is 3.01 LU
    /// apart. An `AVAssetReaderAudioMixOutput` will happily give one channel
    /// to a caller who asks; measuring at a shape the file is not written at
    /// is a silent 3 dB error.
    private static let measureSampleRate: Double = 48000
    private static let measureChannelCount = 2
    private static let measureAudioSettings = ExportAudioGain.floatMixSettings

    /// The same, in the writer's own 16-bit integer. Nothing in this tree had
    /// asked an `AVAssetReaderAudioMixOutput` for float before phase 5, so
    /// the float request is MEASURED with `canAdd` rather than assumed and
    /// this is what a refusal falls back to — a measurement of a signal
    /// clipped at full scale is still better than no measurement, and the
    /// fallback is recorded here rather than discovered as a wrong number.
    ///
    /// **Measured on macOS 26.5.1: the float request is accepted**
    /// (`canAdd` answered true over a composition with one audio track and a
    /// mix, and the pass measured EBU Tech 3341 case 1 at −22.994 LUFS
    /// against its −23.0). So this dictionary is insurance and not a path
    /// anything here has taken; if it ever is taken, the loudness of a mix
    /// with no headroom problem is unaffected and the true peak of one that
    /// has is pinned at 0 dBTP.
    private static let measureFallbackAudioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// Pass one: read the composed mix and measure it. `buildQueue`, never
    /// the main thread.
    ///
    /// The range is the SETTINGS' — `Exporter.timeRange`, the same one the
    /// writer will read — and not the composition's own duration, or the
    /// measurement would cover a different span than the file. No video
    /// output is added, which is the whole reason the pass is cheap.
    ///
    /// nil for a composition with no sound, for a read this Mac refuses, and
    /// for a cancel. A nil is "no loudness figure", never a failed export:
    /// the write that follows is the one that decides whether there is a
    /// file. A normalisation that was asked for and could not be measured
    /// therefore writes UN-normalised, and the missing line on the progress
    /// sheet is how that shows — which is honest for the only case that
    /// reaches it in practice (a timeline with no sound at all), because
    /// every other nil here is a decode failure the write pass runs into a
    /// moment later and reports as the error it is.
    func measureLoudness(
        _ built: BuiltComposition, settings: ExportSettings
    ) -> ExportLoudness? {
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty, let reader = try? AVAssetReader(asset: built.composition),
            let meter = LoudnessMeter(
                sampleRate: Exporter.measureSampleRate,
                channelCount: Exporter.measureChannelCount)
        else { return nil }
        let range = Exporter.timeRange(settings, composition: built.composition)
        let seconds = max(0, CMTimeGetSeconds(range.duration))
        reader.timeRange = range
        // Only the frames the file will hold are measured (spec §11 #337).
        let limit = ExportAudioEnd.frames(ofTicks: CompositionBuilder.ticks(range.duration))
        var fed = 0

        var isFloat = true
        var output = Exporter.mixOutput(tracks, mix: built.audioMix, float: true)
        if !reader.canAdd(output) {
            isFloat = false
            output = Exporter.mixOutput(tracks, mix: built.audioMix, float: false)
            guard reader.canAdd(output) else { return nil }
        }
        reader.add(output)
        guard reader.startReading() else { return nil }
        lock.lock()
        measuring = true
        lock.unlock()
        defer {
            lock.lock()
            measuring = false
            lock.unlock()
        }

        while let sample = output.copyNextSampleBuffer() {
            guard !isCancelled else {
                reader.cancelReading()
                return nil
            }
            fed += feed(sample, to: meter, float: isFloat, limit: limit - fed)
            guard seconds > 0 else { continue }
            let elapsed = CMTimeGetSeconds(
                CMSampleBufferGetPresentationTimeStamp(sample) - range.start)
            setMeasureProgress(min(max(elapsed / seconds, 0), 1))
        }
        guard reader.status == .completed else { return nil }
        setMeasureProgress(1)
        return ExportLoudness.resolve(
            measured: meter.finish(), target: settings.loudnessLufs, ceiling: settings.peakDbtp)
    }

    /// One read-only output over the plan's mix — the same taps, the same
    /// volume ramps the writer will read through.
    private static func mixOutput(
        _ tracks: [AVAssetTrack], mix: AVAudioMix?, float: Bool
    ) -> AVAssetReaderAudioMixOutput {
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: float ? measureAudioSettings : measureFallbackAudioSettings)
        output.audioMix = mix
        // Nothing here writes a sample back, so there is no reason to pay
        // for a copy of every buffer (`MediaImporter.peaks` is the precedent).
        output.alwaysCopiesSampleData = false
        return output
    }

    /// One sample buffer into the meter, at most `limit` frames of it; the
    /// frames fed.
    ///
    /// A `CMBlockBuffer` may be several non-contiguous chunks, and
    /// `CMBlockBufferGetDataPointer` on the first one silently truncates the
    /// buffer — the trap `MediaImporter.peaks` records and
    /// `ReverseRenderer.appendAudioBytes` avoids the same way.
    private func feed(
        _ sample: CMSampleBuffer, to meter: LoudnessMeter, float: Bool, limit: Int
    ) -> Int {
        guard limit > 0, let block = CMSampleBufferGetDataBuffer(sample) else { return 0 }
        let width = float ? MemoryLayout<Float>.size : MemoryLayout<Int16>.size
        let frames = min(
            CMBlockBufferGetDataLength(block) / (width * Exporter.measureChannelCount), limit)
        let byteCount = frames * width * Exporter.measureChannelCount
        guard frames > 0, let bytes = scratch(ofAtLeast: byteCount) else { return 0 }
        guard CMBlockBufferCopyDataBytes(
            block, atOffset: 0, dataLength: byteCount, destination: bytes)
            == kCMBlockBufferNoErr
        else { return 0 }
        if float {
            meter.feed(
                bytes.bindMemory(to: Float.self, capacity: byteCount / width), frames: frames)
        } else {
            meter.feedInt16(
                bytes.bindMemory(to: Int16.self, capacity: byteCount / width), frames: frames)
        }
        return frames
    }

    private func scratch(ofAtLeast bytes: Int) -> UnsafeMutableRawPointer? {
        if scratchCapacity < bytes {
            scratchStorage?.deallocate()
            scratchStorage = .allocate(byteCount: bytes, alignment: 16)
            scratchCapacity = bytes
        }
        return scratchStorage
    }
}
