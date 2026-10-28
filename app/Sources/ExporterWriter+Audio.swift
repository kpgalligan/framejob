import AVFoundation

// `ExportWriter`'s audio half: the audio writer input and the mix's reader output. A pure
// move out of `ExporterWriter.swift` at its size cap (issue #378), before its readers were
// split one per output; the members each file calls in the other lost `private` (`built`,
// `audioOutput`, `addAudio`, `addAudioOutput`; `audioGain` became `private(set)`), and
// nothing else changed.
extension ExportWriter {

    /// The audio half: every composition audio track through the plan's mix.
    ///
    /// **`addAudioOutput`'s `audioMix` line is where the preview and the file
    /// agree about sound.**
    /// The mix carries the plan's volume envelope AND, for any track whose
    /// clips use pan, the compressor or noise reduction, the
    /// `MTAudioProcessingTap` that runs them (`AudioTap.swift`). Those taps
    /// were long believed to be an AVPlayer-only feature — true of the
    /// `AVAssetExportSession` this pipeline replaced, and the reason the
    /// effects were left unimplemented — but measured against
    /// `AVAssetReaderAudioMixOutput` they run here as well: a tap that
    /// silenced its buffers produced a silent file, one tap per track saw only
    /// its own track, and with `reader.timeRange` set for an in/out export the
    /// tap is handed COMPOSITION time, so a clip's settings still line up with
    /// the clip. Nothing had to be re-implemented for the export; the DSP has
    /// one implementation and this reads through it.
    ///
    /// The one thing the file and the preview do not share is the reducer's
    /// 512-sample delay on a track that uses it, which both paths have and
    /// neither compensates: 10.7 ms of audio lag at 48 kHz, well inside every
    /// A/V sync tolerance, on tracks the user asked to clean.
    ///
    /// A timeline with no audio at all is not an error — it is a silent
    /// movie, and the track is simply not added. It IS an error when the
    /// preset writes nothing else.
    ///
    /// This adds the writer INPUT only. The reader output is added by `start`
    /// (`addAudioOutput`), because its format depends on the gain, which
    /// arrives after `init`.
    func addAudio(settings: ExportSettings) throws {
        let tracks = built.composition.tracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            if settings.isAudioOnly { throw Exporter.ExportError.emptyTimeline }
            return
        }
        let input = AVAssetWriterInput(
            mediaType: .audio, outputSettings: Self.audioSettings(settings))
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else {
            throw Exporter.ExportError.presetUnavailable(Self.presetName(settings))
        }
        writer.add(input)
        audioInput = input
    }

    /// The mix's reader output (`audioReadOutput`). False when the reader
    /// refuses it; there is no 16-bit fallback for a gained export, because
    /// the gain would then meet a decode that already clipped.
    func addAudioOutput() -> Bool {
        let output = Self.audioReadOutput(built, gained: audioGain != nil)
        guard let audioReader, audioReader.canAdd(output) else { return false }
        audioReader.add(output)
        audioOutput = output
        return true
    }
}
