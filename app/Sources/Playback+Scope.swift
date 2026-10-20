import Foundation

/// A scope change's half of `Playback` (#130): the seek that lands the player in the NEW
/// container, and the end of a hold whose rebuild will not land (#185). The first is a pure
/// move out of `Playback.swift` (issue batch B30), which sat at the 600-line cap; the seek
/// state both write stays there, internal for this file alone, because an extension cannot
/// add stored properties. A seek's landing (`seekFinished`) and `onTimeChanged`'s one caller
/// (`report`) are a second pure move (hdr H-3), with `reported` and `refreshWanted` widened.
extension Playback {
    /// A scope change's seek (#130): `t` is in the container `update` was just handed, so the
    /// OUTGOING item is neither sought nor heard, and a rebuild in flight lands there, heard once.
    func seekAfterRebuild(to t: Ticks) {
        seekSerial += 1
        pendingSeek = nil
        restoring = true
        lastKnownTime = max(0, t)
        guard rebuilding else {
            isSeeking = false
            startSeek(to: t)
            return
        }
        holding = true
        isSeeking = true
    }

    /// Ends a held scope change whose rebuild will not land — it failed, or the new plan is
    /// empty — once the caller has dropped the item (#185): the held time is kept, and with no
    /// item to seek, `startSeek` reports it once.
    func endHoldWithoutItem() {
        holding = false
        isSeeking = false
        restoring = false
        pendingSeek = nil
        startSeek(to: lastKnownTime)
    }

    /// One seek has landed: take the newest position that arrived while it
    /// was in flight, if any, dropping the rest; else end it — a restore or an
    /// asked seek alike — heard once only if it rests off the tick last
    /// reported (the observer may have carried it already); then any paused
    /// refresh waiting.
    func seekFinished() {
        isSeeking = false
        if let next = pendingSeek {
            pendingSeek = nil
            startSeek(to: next)
            return
        }
        restoring = false
        let rest = currentTime
        if rest != reported { report(rest) }
        if refreshWanted { refreshPausedFrame() }
    }

    /// The ONE caller of `onTimeChanged`.
    func report(_ t: Ticks) {
        reported = t
        onTimeChanged?(t)
    }
}
