// app/Sources/GraphicPrefetch+Background.swift — a background session's own
// branches (spec §11 G-38, issue #127): a paused document's pass from the
// playhead straight into its kept frames. Moved whole out of
// `GraphicPrefetch.swift` (a pure move under the size cap, #596); `start`'s
// refusal and its `beginAhead` line, `claim`'s and `insert`'s `full` arms,
// `stop`'s and `work`'s end lines and `logLine`'s pass branch stay there, each
// one statement inside a lock hold or a wait loop.
//
// `stopBackground` takes `condition` itself; the other two run under it, called
// by `draw` and `finish` only for a background session that is not stopped.

import Foundation

extension GraphicPrefetch {
    /// `stop(key)` for every background session, no other. Main only.
    func stopBackground() {
        condition.lock()
        let keys = sessions.values.filter(\.background).map(\.key)
        condition.unlock()
        for key in keys { stop(key) }
    }

    /// A pass's job left to the compositor (`draw`'s same-texture shortcut):
    /// its entry leaves its slot, a raster the key already keeps is marked
    /// drawn ahead, else the earlier unfinished entry drawing `key` takes it as
    /// a sharer. Under `condition`.
    func passDeferred(_ job: Job, key: String, keptAlready: Bool, in session: Session) {
        if session.slots[job.slot] === job.entry { session.slots[job.slot] = nil }
        if keptAlready, kept.raster(session.key, key) != nil {
            kept.markAhead(session.key, key, index: job.entry.index)
            session.alreadyKept += 1
        } else if let first = session.slots.values.first(where: {
            !$0.done && $0.textureKey == key && $0.index < job.entry.index
        }) {
            (first.sharers, first.sharedUpTo) =
                (first.sharers + 1, max(first.sharedUpTo, job.entry.index))
        }
    }

    /// A pass's finished job: its entry leaves its slot, and a raster kept is
    /// marked drawn ahead through its last sharer's frame. Under `condition`.
    func passFinished(_ job: Job, in session: Session) {
        if session.slots[job.slot] === job.entry { session.slots[job.slot] = nil }
        if release(job.entry, from: session), let textureKey = job.entry.textureKey {
            let entry = job.entry
            kept.markAhead(session.key, textureKey, index: max(entry.index, entry.sharedUpTo))
            (session.drawn, session.alreadyKept) =
                (session.drawn + 1, session.alreadyKept + entry.sharers)
        }
    }
}
