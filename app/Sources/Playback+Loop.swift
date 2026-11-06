import AVFoundation

/// A loop at the item's end (#466). The periodic observer wraps a loop ending
/// before the item does; one ending at the item's end can be overtaken by the
/// item itself, so `syncItemEndAction` holds the player running there. Under
/// `.none` its clock runs on past the end, so whichever hears it first wraps:
/// the periodic observer, for a loop ending on the item's end, or the item-end
/// notification, the only one that can for a loop running past it.
extension Playback {

    /// The tick a loop wraps at: the loop's end, or the item's when the loop runs past it.
    /// Nil with no loop, a loop of no length, no built composition, or a loop starting at or past the item's end.
    var loopEnd: Ticks? {
        guard let loop = loopRange, loop.duration > 0, let built = built else { return nil }
        let itemEnd = CompositionBuilder.ticks(built.composition.duration)
        guard loop.start < itemEnd else { return nil }
        return min(loop.start + loop.duration, itemEnd)
    }

    /// The item reached its end (AVPlayerItem.didPlayToEndTimeNotification, main queue).
    ///
    /// The post can arrive after the world moved. Loop off, or an edit leaving
    /// the loop past the end, must stop here: with `.none` still in force the
    /// player would run on at the end. A tick that already wrapped must not
    /// wrap again, which is what the one frame of slack is for; during a seek
    /// `currentTime` is that seek's target. The rate is never touched, so ×2
    /// and ×4 hold.
    func itemPlayedToEnd() {
        guard rate > 0 else { return }
        guard let end = loopEnd, let loop = loopRange else {
            pause()
            return
        }
        let frame = built.map { CompositionBuilder.ticks($0.videoConfiguration.frameDuration) } ?? 0
        guard currentTime >= end - frame else { return }
        seek(to: loop.start)
    }
}
