import Foundation

/// A scope change's half of `Playback` (#130): the seek that lands the player in the NEW
/// container, and the end of a hold whose rebuild will not land (#185). The first is a pure
/// move out of `Playback.swift` (issue batch B30), which sat at the 600-line cap; the seek
/// state both write stays there, internal for this file alone, because an extension cannot
/// add stored properties. A seek's landing (`seekFinished`) and `onTimeChanged`'s one caller
/// (`report`) are a second pure move (hdr H-3), with `reported` and `refreshWanted` widened.
/// The paused refresh (`refreshPausedFrame`) is a third (#568), reading `rate` and `currentItem`.
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
        #if FRAMEJOB_DEV_TOOLS
        rebuildLog.landed()
        #endif
        let rest = currentTime
        if rest != reported { report(rest) }
        if refreshWanted { refreshPausedFrame() }
    }

    /// The ONE caller of `onTimeChanged`.
    func report(_ t: Ticks) {
        reported = t
        onTimeChanged?(t)
    }

    /// Forces one composed frame while paused, for a recipe that changed
    /// under an item that did not (a property-only edit, spec §7.6).
    ///
    /// The standard trick, a zero-tolerance seek to the time the player is
    /// already at, is a NO-OP on macOS 26.5.1 (measured by
    /// `tools/proof/preview_refresh_probe.py`: the completion fires, no
    /// composition request is issued; re-assigning `videoComposition` and
    /// `AVPlayerItem.seek` are the same no-op). Only a seek to a DIFFERENT
    /// time composes, so this steps one tick off the playhead — inside the
    /// same frame, so the picture between the two seeks is the picture — with
    /// the return queued as `pendingSeek`, and lands back on the playhead's
    /// own tick with the new recipe drawn. Parked AT the end, as a transport
    /// that played through is, it rests on the last frame's final tick
    /// instead: the end tick composes nothing (every seek to it, tolerant or
    /// not, displays black — measured), so a return there would blank it.
    ///
    /// Both seeks are a RESTORE, not a playhead move: `onTimeChanged` hears
    /// neither jump, and hears the landing only when it differs from the tick
    /// last reported — which the end branch's `end - 1` does, once.
    func refreshPausedFrame() {
        refreshWanted = false
        guard rate == 0, currentItem != nil else { return }
        if isSeeking {
            refreshWanted = true
            return
        }
        let here = currentTime
        let end = built.map { CompositionBuilder.ticks($0.composition.duration) } ?? 0
        if here >= end {
            if end >= 1 {
                restoring = true
                startSeek(to: end - 1)
            }
            return
        }
        let step = here + 1 < end ? here + 1 : here - 1
        guard step >= 0 else { return }
        restoring = true
        startSeek(to: step)
        startSeek(to: here)
    }
}
