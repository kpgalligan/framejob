import Foundation

/// The filmstrip's and the waveform's source time through a clip's source
/// map (spec §11 SR-20 (d)). `TimelineView.swift` is frozen, so the
/// map-aware form lives here beside the three-argument one it falls back to.
extension TimelineView {
    /// Source time under a timeline time, for the filmstrip and the waveform.
    /// A RAMPED map reads `⌊S(t − start)⌋` off the core's pairs, mirrored
    /// about the media's duration when the clip plays backwards, as the
    /// three-argument form mirrors (`ReverseMirror`, spec §11 D4-6). A
    /// constant map, or none, is the three-argument form exactly, so a
    /// constant clip draws as it did (SR-20 (b)).
    static func sourceTime(
        of clip: ClipSnapshot, in media: MediaSnapshot, at t: Ticks, map: SourceMap?
    ) -> Ticks {
        guard let map = map, map.ramped else { return sourceTime(of: clip, in: media, at: t) }
        let read = map.source(atClip: Double(t - clip.start)).rounded(.down)
        let source = TimelineLayout.ticks(clamping: read)
        guard clip.source.isReversed else { return source }
        return ReverseMirror.mirrored(source, about: media.duration)
    }
}
