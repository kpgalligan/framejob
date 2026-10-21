import CoreMedia
import Foundation

/// A playing preview's graphics prefetch (issue #127, spec §11 G-36): the
/// workers `GraphicPrefetch` runs for an export, run on this document's own
/// key while the transport plays forward over a project that draws a graphic.
/// The compositor stays the one consumer and the texture key decides, so
/// every frame is the serial path's (G-26 (c)).
///
/// `Playback.swift` calls `syncPrefetch(from:)` at the three moments the
/// session's start can move — the rate KVO, `startSeek` (with the seek's
/// TARGET, never `currentTime`, which still reads the player there) and a
/// property-only edit while playing — and stops the session in `invalidate`
/// and `deinit`. An item swap needs no call of its own: `finishRebuild`'s
/// `startSeek` and its rate restore cover it. This file only reads the
/// transport's state; the seek and restore rules stay `Playback.swift`'s.
extension Playback {
    /// Stops this document's playback session, then starts a fresh one at
    /// `start` when the live rate is above 0, an item is built and the
    /// project draws a graphic; `seeking` when a seek to `start` begins it
    /// (its session follows from the seek's own frame, G-36 (d)). Main only.
    ///
    /// The grid (G-36 (b)): `start` snapped down onto the composition's frame
    /// grid from 0, at the built composition's `frameDuration`, to the in/out
    /// range's end while playback loops inside it, else to the composition's
    /// end.
    func syncPrefetch(from start: Ticks, seeking: Bool = false) {
        GraphicPrefetch.shared.stop(recipeKey)
        guard rate > 0, let built, drawsGraphics else { return }
        let frameDuration = built.videoConfiguration.frameDuration
        let frame = CompositionBuilder.ticks(frameDuration)
        guard frame > 0 else { return }
        let first = max(0, start) / frame * frame
        var end = CompositionBuilder.ticks(built.composition.duration)
        if let loop = loopRange, loop.duration > 0, start < loop.start + loop.duration {
            end = min(end, loop.start + loop.duration)
        }
        guard end > first else { return }
        GraphicPrefetch.shared.start(
            key: recipeKey,
            range: CMTimeRange(
                start: CompositionBuilder.time(first), end: CompositionBuilder.time(end)),
            frameDuration: frameDuration, follows: true, seeking: seeking)
    }

    /// Whether `snapshot` draws a graphic clip: on the timeline, or in any
    /// nest.
    static func drawsGraphics(_ snapshot: ProjectSnapshot) -> Bool {
        snapshot.clips.contains { $0.graphic != nil }
            || snapshot.nests.contains { nest in nest.clips.contains { $0.graphic != nil } }
    }
}
