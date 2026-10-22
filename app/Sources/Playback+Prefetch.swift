import CoreMedia
import Foundation

/// A playing preview's graphics prefetch (issue #127, spec §11 G-36): the
/// workers `GraphicPrefetch` runs for an export, run on this document's own
/// key while the transport plays forward over a project that draws a graphic.
/// The compositor stays the one consumer and the texture key decides, so
/// every frame is the serial path's (G-26 (c)).
///
/// Every `syncPrefetch` is also activity for the idle clock, and
/// `startBackgroundRender()` is the clock's door to a paused pass (G-38,
/// `BackgroundRender.swift`).
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
        BackgroundRender.shared.noteActivity(from: self)
        GraphicPrefetch.shared.stop(recipeKey)
        guard rate > 0, let built, drawsGraphics else { return }
        guard let grid = prefetchGrid(from: start, built: built) else { return }
        GraphicPrefetch.shared.start(
            key: recipeKey, range: grid.range, frameDuration: grid.frameDuration, follows: true,
            seeking: seeking)
    }

    /// The idle clock's pass (G-38 (c)): busy while a seek, a restore, a
    /// rebuild or a hold is in flight, or when `GraphicPrefetch` refuses (a
    /// pass or a play runs); not needed unless paused over a built item that
    /// draws a graphic, with the document's graphics still registered (an
    /// open document), a grid from the playhead, the prefetch switch off and
    /// a key that keeps (G-38 (e): so neither switch re-arms the clock).
    /// Main only.
    func startBackgroundRender() -> BackgroundStart {
        if isSeeking || restoring || rebuilding || holding { return .busy }
        guard rate == 0, drawsGraphics, let built = built,
            GraphicRegistry.shared.resolve(recipeKey) != nil,
            !UserDefaults.standard.bool(forKey: GraphicPrefetch.offDefaultsKey),
            GraphicPrefetch.shared.keeps(recipeKey),
            let grid = prefetchGrid(from: currentTime, built: built)
        else { return .notNeeded }
        let started = GraphicPrefetch.shared.start(
            key: recipeKey, range: grid.range, frameDuration: grid.frameDuration,
            background: true)
        return started ? .started : .busy
    }

    /// G-36 (b)'s grid from `start`: snapped down onto the composition's
    /// frame grid from 0, at the built composition's `frameDuration`, to the
    /// in/out range's end while playback loops inside it, else to the
    /// composition's end. Nil when empty.
    private func prefetchGrid(
        from start: Ticks, built: BuiltComposition
    ) -> (range: CMTimeRange, frameDuration: CMTime)? {
        let frameDuration = built.videoConfiguration.frameDuration
        let frame = CompositionBuilder.ticks(frameDuration)
        guard frame > 0 else { return nil }
        let first = max(0, start) / frame * frame
        var end = CompositionBuilder.ticks(built.composition.duration)
        if let loop = loopRange, loop.duration > 0, start < loop.start + loop.duration {
            end = min(end, loop.start + loop.duration)
        }
        guard end > first else { return nil }
        let range = CMTimeRange(
            start: CompositionBuilder.time(first), end: CompositionBuilder.time(end))
        return (range, frameDuration)
    }

    /// Whether `snapshot` draws a graphic clip: on the timeline, or in any
    /// nest.
    static func drawsGraphics(_ snapshot: ProjectSnapshot) -> Bool {
        snapshot.clips.contains { $0.graphic != nil }
            || snapshot.nests.contains { nest in nest.clips.contains { $0.graphic != nil } }
    }
}
