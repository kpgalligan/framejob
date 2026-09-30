import AVFoundation
import CoreMedia
import Foundation

/// The await-free half of the speech cache — `speechIsCurrent` (the head
/// check `speech(for:url:stamp:into:)` runs before it does anything) and
/// `writeSpeech` (the reader and the Silero pass itself, which run entirely
/// on `copyNextSampleBuffer` and `SileroVAD.feed`/`flush`, neither of which
/// awaits). An `extension MediaImporter` in a file of its own for the same
/// reason `MediaCacheFiles.swift` is: `async`/`await` is confined to
/// `MediaImporter.swift`, and this is the piece of the pass that does not
/// need it.
extension MediaImporter {

    /// Whether the speech cache for `media` is already current: a stamp,
    /// a marker equal to `SpeechStamp(stamp)`, and the `.bin` actually there.
    /// A nil stamp (the file could not be stat'ed) never says yes.
    static func speechIsCurrent(for media: MediaSnapshot, stamp: CacheStamp?, in cacheDir: URL)
        -> Bool
    {
        guard let stamp else { return false }
        let marker = speechMarkerURL(for: media.id, in: cacheDir)
        guard readSpeechStamp(at: marker) == SpeechStamp(stamp) else { return false }
        return FileManager.default.fileExists(atPath: speechURL(for: media.id, in: cacheDir).path)
    }

    /// Writes `cache/speech/<id>.bin`: one Silero VAD probability per
    /// `MediaSpeech.chunkTicks` of source time, read from a 16 kHz mono float
    /// extraction of `track` (the spike's own output settings, NOT
    /// `Transcriber.extractSettings`'s 16-bit int — the model wants float).
    ///
    /// A `canAdd`/`startReading` failure returns silently, `peaks`' posture:
    /// no marker, no `.bin`, retried on the next open. `SileroVAD.bundled()`
    /// answering nil means it has already `markUnavailable`d and logged, so
    /// this returns too. Probabilities land in a zero-filled buffer sized by
    /// `chunkCount(duration:)` from index 0; extra chunks past that (a track
    /// slightly longer than the record's `duration`) are dropped. A thrown
    /// `feed`/`flush` calls `markUnavailable` itself — the Core ML failure of
    /// road map 4's §4a — which is what turns `SileroVAD.isAvailable` false
    /// for the whole process rather than leaving one media `pending` for
    /// ever.
    static func writeSpeech(
        for media: MediaSnapshot, asset: AVURLAsset, track: AVAssetTrack, stamp: CacheStamp?,
        into cacheDir: URL, pass: CachePass? = nil
    ) {
        guard let vad = SileroVAD.bundled() else { return }
        guard let reader = try? AVAssetReader(asset: asset) else { return }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Double(SileroVAD.sampleRate),
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

        var probabilities = [Float](
            repeating: 0, count: MediaSpeech.chunkCount(duration: media.duration))
        var index = 0
        var failed = false

        func absorb(_ values: [Float]) {
            for value in values {
                guard index < probabilities.count else { break }
                probabilities[index] = value
                index += 1
            }
        }

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
            do {
                absorb(try vad.feed(samples))
            } catch {
                SileroVAD.markUnavailable("\(error)")
                reader.cancelReading()
                failed = true
                break
            }
        }
        // BEFORE the cancel, which would make every status `.cancelled`: the
        // loop above ends on a nil buffer, and a nil buffer means the track
        // ran out OR the decode gave up part way. The second leaves the rest
        // of `probabilities` at ZERO, and zero is "nobody is talking" — so a
        // file whose middle will not decode would be certified by the marker
        // below and its whole undecodable tail proposed for removal in voice
        // mode (measured on a corrupt AAC: the reader stops at 2.05 s of a
        // 10.4 s file and 8.1 s of it was proposed). `peaks` now also
        // requires a completed reader and full accepted PCM coverage (#23).
        // Refusing here is `writeSpeech`'s stated posture for a reader
        // that will not build or start (§4a): no `.bin`, no marker, retried on
        // the next open, and the media stays `voice_pending` — never quiet —
        // until it decodes.
        let status = reader.status
        reader.cancelReading()
        guard !failed, status == .completed else { return }
        do {
            if let tail = try vad.flush() { absorb([tail]) }
        } catch {
            SileroVAD.markUnavailable("\(error)")
            return
        }

        let file = speechURL(for: media.id, in: cacheDir)
        let data = probabilities.withUnsafeBufferPointer { Data(buffer: $0) }
        // The directory, the `.bin`, its marker and the post: one publication.
        CacheLedger.shared.publish(in: cacheDir, for: pass) {
            guard ensureDirectory(file.deletingLastPathComponent()) else { return }
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
            if let stamp {
                writeStamp(SpeechStamp(stamp), to: speechMarkerURL(for: media.id, in: cacheDir))
            }
            postCacheChange(media: media.id, kind: speechKind)
        }
    }
}
