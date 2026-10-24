import AVFoundation

/// Bundled silence for a composition audio track with no source (spec §11
/// #336): a track none of whose segments resolved — missing media, a pending
/// reverse, a pending ramp render — is nothing but empty edits, and an export
/// of a composition whose audio is only such a track fails ("The operation
/// could not be completed", measured by `tools/proof/missing_audio_proof.py`).
/// Real silence over the same span reads; the track's id, input parameters,
/// envelope, onset, meter and `sounding` spans stay exactly what they were.
///
/// **The resource**, `app/Resources/Silence.caf`: 10.000 s of digital
/// silence, 48 kHz (spec §11 SY-23), two channels, ALAC from 16-bit, made by
///
///     python3 -c "import wave; w=wave.open('s.wav','wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(48000); w.writeframes(bytes(4*480000)); w.close()"
///     afconvert -f caff -d alac s.wav app/Resources/Silence.caf
///
/// and checked with `afinfo` (480000 frames, 48000 Hz, 2 ch, `alac`).
/// Where it is absent — the probes and the harness bundle no app resources —
/// the track keeps its empty edits, as `addPlaceholderIfNeeded` keeps no
/// placeholder without `Blank.mp4`.
extension CompositionBuilder {

    /// "Silence" / "caf" in `Bundle.main`.
    static let silenceName = "Silence"

    /// The end (ticks) of a family none of whose segments resolved: no
    /// `sounding` span, and a segment ending after 0. Else nil.
    static func silentEnd(of family: AudioFamily) -> Ticks? {
        guard family.sounding.isEmpty,
            let end = family.segments.map({ $0.start + $0.duration }).max(), end > 0
        else { return nil }
        return end
    }

    /// When `silentEnd(of:)` answers, the resource and its first audio track
    /// resolve, and its extent is numeric and floors to at least one tick:
    /// that floored extent inserted back to back from 0, never scaled, the
    /// last copy cut at the end, and true. Otherwise nothing is touched and
    /// the answer is false, so the caller fills the track as before. The
    /// guarded extent is `heldTail`'s rule, so the loop always advances.
    static func fillSilence(
        _ track: AVMutableCompositionTrack, for family: AudioFamily
    ) throws -> Bool {
        guard let end = silentEnd(of: family),
            let url = Bundle.main.url(forResource: silenceName, withExtension: "caf")
        else { return false }
        let asset = AVURLAsset(url: url)
        return try withExtendedLifetime(asset) { () throws -> Bool in
            guard let source = firstTrack(of: asset, mediaType: .audio) else { return false }
            let extent = timeRange(of: source)
            guard extent.start.isNumeric, extent.end.isNumeric else { return false }
            let copy = CMTimeConvertScale(
                extent.duration, timescale: CMTimeScale(ReelTime.perSecond),
                method: .roundTowardZero
            ).value
            guard copy >= 1 else { return false }
            var at: Ticks = 0
            while at < end {
                let length = min(copy, end - at)
                do {
                    try track.insertTimeRange(
                        CMTimeRange(start: extent.start, duration: time(length)),
                        of: source, at: time(at))
                } catch {
                    throw BuildError.insertFailed(
                        clip: family.segments[0].clip, underlying: error)
                }
                at += length
            }
            return true
        }
    }
}
