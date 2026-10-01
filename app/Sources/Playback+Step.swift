import Foundation

/// The arrow keys' frame step. A pure move out of `Playback.swift`, which sat at the 600-line cap
/// (issue batch B21). The main hop `onMain` is a second pure move out of it (issue batch B53).
extension Playback {
    /// Steps `n` frames (negative steps back) and pauses: stepping while
    /// playing means nothing, and the arrow keys are how a cut is placed
    /// exactly (§9).
    func stepFrames(_ n: Int, fps: Fps) {
        let step = fps.frameDuration
        guard step > 0, n != 0 else { return }
        pause()
        seek(to: max(0, currentTime + Ticks(n) * step))
    }

    /// AVFoundation calls KVO and seek completions on whichever thread it
    /// happens to be on. Everything here touches AppKit state, so hop when
    /// needed — `OperationQueue.main`, not a new dispatch seam.
    func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread {
            body()
        } else {
            OperationQueue.main.addOperation(body)
        }
    }
}
